{lib, pkgs, config, ...}:
let cfg = config.services.ghc-perf-import;
in{
  options.services.ghc-perf-import = {
    enable = lib.mkEnableOption "Enable ghc-perf-import service";
    gitlab-token-path = lib.mkOption{
      type = lib.types.path;
      description = "Path to file holding GitLab access token";
    };
    user = lib.mkOption{
      type = lib.types.str;
      default = "ghc_perf";
    };
    group = lib.mkOption{
      type = lib.types.str;
      default = "ghc_perf";
    };
    dbName = lib.mkOption{
      type = lib.types.str;
      default = "ghc_perf";
    };
    dbSchema = lib.mkOption{
      type = lib.types.path;
    };
    gitlab-bot-package = lib.mkOption {
      type = lib.types.package;
      description = "The gitlab-bot package";
    };
    ghc-note-perf-import-package = lib.mkOption {
      type = lib.types.package;
      description = "The ghc-perf-import package";
    };
    git-package = lib.mkOption {
      type = lib.types.package;
      description = "git package";
      default = pkgs.git;
    };
  };
  config = lib.mkIf cfg.enable {

    systemd.services.ghc-perf-import-gitlab-bot = {
      description = "ghc-perf metric import bot";
      script = ''
        ghc-perf-import-service \
          --gitlab-root=https://gitlab.haskell.org/ \
          --access-token-path=${config.services.ghc-perf-import.gitlab-token-path} \
          --conn-string=postgresql:///ghc_perf \
          --port=7088
      '';
      path = [ cfg.git-package cfg.gitlab-bot-package cfg.ghc-note-perf-import-package ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "${cfg.user}";
        PermissionsStartOnly = true;
        CacheDirectory = "ghc-perf";
      };
    };
    systemd.services.ghc-note-perf-import = {
      description = "Update ghc-perf metrics from perf notes";
      preStart = ''
    if ! ${pkgs.sudo}/bin/sudo -upostgres ${pkgs.postgresql}/bin/psql -lqtA | grep -q "^${cfg.dbName}|"; then
      echo "Initializing schema..."
      ${pkgs.sudo}/bin/sudo -upostgres ${pkgs.postgresql}/bin/psql \
        -c "CREATE ROLE ghc_perf_web WITH LOGIN;" \
        -c "CREATE ROLE ghc_perf WITH LOGIN;" \
        -c "CREATE DATABASE ${cfg.dbName} WITH OWNER ghc_perf;"
      ${pkgs.sudo}/bin/sudo -ughc_perf ${pkgs.postgresql}/bin/psql -U ghc_perf < ${cfg.dbSchema}
      ${pkgs.sudo}/bin/sudo -upostgres ${pkgs.postgresql}/bin/psql \
        -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO ghc_perf_web;"
      echo "done."
    fi
      '';
      script = ''
    cd /var/cache/ghc-perf
    if [ ! -d ghc ]; then
      echo "cloning $(pwd)/ghc..."
      ${cfg.git-package}/bin/git clone https://gitlab.haskell.org/ghc/ghc
    fi
    cd ghc

    echo "updating $(pwd)/ghc..."
    ${cfg.git-package}/bin/git pull
    ${cfg.git-package}/bin/git fetch https://gitlab.haskell.org/ghc/ghc-performance-notes.git refs/notes/perf:refs/notes/ci/perf

    echo "importing commits..."
    perf-import-git -c postgresql:///${cfg.dbName} -d ghc master

    echo "importing notes..."
    perf-import-notes -c postgresql:///${cfg.dbName} -d ghc -R refs/notes/ci/perf
      '';
      path = [ pkgs.git cfg.ghc-note-perf-import-package ];
      serviceConfig = {
        User = "${cfg.user}";
        PermissionsStartOnly = true;
        CacheDirectory = "ghc-perf";
      };
    };

    systemd.timers.ghc-note-perf-import = {
      description = "Periodically update ghc-perf metrics";
      wants = [ "network.target" "postgresql.service" ];
      after = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 3:00:00";
        Unit = "ghc-note-perf-import.service";
      };
    };

    users.users."${cfg.user}" = {
      description = "User for ghc-perf import script";
      isSystemUser = true;
      group = cfg.group;
    };

    users.groups."${cfg.group}" = {};

  };
}
