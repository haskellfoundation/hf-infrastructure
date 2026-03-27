{ lib, pkgs, config, ... }:
let
  cfg = config.services.hackage-metadata-refresh;
  name = "hackage-metadata-refresh";
  mkRuntimeSecrets = keys:
    lib.attrsets.genAttrs
      (map (k: "${name}/runtime/${k}") keys)
      (_: { owner = name; });
in {
  options.services.hackage-metadata-refresh = {
    enable = lib.mkEnableOption "Hackage metadata refresh service";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1003;
      description = "UID for the hackage-metadata-refresh user";
    };

    package = lib.mkOption {
      type = lib.types.package;
      description = "The all-cabal-tool package";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ssh.knownHostsFiles = [ ../../github_host_keys ];
    users.groups.${name} = {
      gid = cfg.uid;
    };
    users.users.${name} = {
      uid = cfg.uid;
      isNormalUser = true;
      group = name;
      home = "/home/${name}";
      createHome = true;
    };
    sops.secrets = {
      "${name}/ssh_key" = {
        owner = name;
        path = "/home/${name}/.ssh/id_rsa";
      };
    } // mkRuntimeSecrets
      [ "aws_access"
        "aws_secret"
        "s3_bucket"
      ];
    systemd.services.${name} = {
      description = "Refresh hackage metadata";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        User = name;
        Restart = "on-failure";
        RestartSec = 1;
        LoadCredential = "creds:/run/secrets/${name}/runtime";
        # sop.secrets provides ~/.gnupg/secring.gpg, but with wrong
        # permissions. Fix before starting the unit.
        ExecStartPre = [
          "+${pkgs.coreutils}/bin/chmod 700 /home/${name}/.gnupg"
          "+${pkgs.coreutils}/bin/chown ${name}:${name} /home/${name}/.gnupg"
        ];
      };
      script = ''
          ${cfg.package}/bin/all-cabal-tool \
            --username all-cabal-tool \
            --email michael+all-cabal-files@snoyman.com \
            --gpg-sign D6CF60FD \
            --s3-bucket "$(< "$CREDENTIALS_DIRECTORY/creds_s3_bucket")" \
            --aws-access-key "$(< "$CREDENTIALS_DIRECTORY/creds_aws_access")" \
            --aws-secret-key "$(< "$CREDENTIALS_DIRECTORY/creds_aws_secret")"
      '';
      path = [ pkgs.git pkgs.gnupg pkgs.openssh ];
    };
  };
}
