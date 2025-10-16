{ config, lib, ...}:
let
  telegrafDb = "telegraf";
  telegrafDbUser = "telegraf";
  # Needs to match the user used in the grafana service, which is hard-coded.
  grafanaDbUser= "grafana";
in
{
  services.telegraf.enable = true;
  services.telegraf.extraConfig = {

    inputs = {
      # TODO: use namepass to restrict the fields we get

      # Other interesting plugins:
      # - smart (S.M.A.R.T.)
      # - nginx (accepts, active, handled, reading, requests, waiting, writing)
      # - exec, execd (run a given command and read its output)
      # - netstat (TCP connection states)
      # - socketstat (ss)
      # - wireguard

      zfs = {
        poolMetrics = true;
        # dataset metrics only available on FreebSD
      };

      # I'm told this data isn't avail from any plugin, but it is easy enough to
      # get:
      # TODO
      # exec = {
      #   zfs list -Hp -o name,used,avail,refer,quota,mountpoint
      #   ...
      # };

      cpu = {};
      mem = {};

      # not useful to us since we're zfs'd
      # disk = {};
      # IO stats. Maybe we can just use zfs for this, too. Yeah, zfs_pool
      # nread/nwritten
      #diskio = {};

      # Causes a segfault lol
      #postgresql = {};

      # Raw bytes
      net = {};
      # TCP stats
      nstat = {};
    };

    outputs.postgresql = {
      connection = "dbname=${telegrafDb}";
      timestamp_column_type = "timestamp with time zone";
      create_templates = [
        "CREATE TABLE {{ .table }} ({{ .columns }})"
        "SELECT create_hypertable({{ .table|quoteLiteral }}, by_range('time', INTERVAL '1 week'), if_not_exists := true)"
        ''grant select on all tables in schema public to "${grafanaDbUser}"''
        ''grant select on all sequences in schema public to "${grafanaDbUser}"''
      ];
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ telegrafDb ];
    ensureUsers = [
      {
        name = telegrafDbUser;
        ensureDBOwnership = true;
      }
      { name = grafanaDbUser; }
    ];
    # Unemcumbered Apache-licensed version.
    extensions = ps: [ ps.timescaledb-apache ];
    settings.shared_preload_libraries = [ "timescaledb" ];
  };
  systemd.services.postgresql.postStart = lib.mkAfter ''
    $PSQL ${telegrafDb} -c 'grant select on all tables in schema public to "${grafanaDbUser}"'
    $PSQL ${telegrafDb} -c 'grant select on all sequences in schema public to "${grafanaDbUser}"'
  '';

  services.grafana = {
    enable = true;
    settings.server.http_port = 8600;

    provision = {
      enable = true;
      datasources = {
        settings = {
          datasources = [
            {
              name = "TimescaleDB (Postgres)";
              type = "postgres";
              url = "/var/run/postgresql";
              user = grafanaDbUser;
              jsonData = {
                database = telegrafDb;
                sslmode = "disable";
                timescaledb = true;
              };
            }
          ];
        };
      };
    };
  };
}
