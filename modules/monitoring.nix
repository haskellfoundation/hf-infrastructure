{ config, ...}:
let
  dbName = "telegraf";
  dbUser = "telegraf";
in
{
  services.telegraf.enable = true;
  services.telegraf.extraConfig = {

    inputs = {
      # Interesting plugins:
      # - nstat (kernel network stats)
      # - smart (S.M.A.R.T.)
      # - disk, diskio (maybe irrelevant with zfs)
      # - nginx (accepts, active, handled, reading, requests, waiting, writing)
      # - linux_cpu (scaling and throttling)
      # - exec, execd (run a given command and read its output)
      # - net
      # - netstat
      # - socketstat (ss)
      # - wireguard
      # - postgresql
      #
      # Let's start with zfs, cpu, and mem
      # Update: zfs is just arc stats and other low-level things I don't care
      # about right now. Dropping.
      cpu = {};
      mem = {};
    };

    outputs.postgresql = {
      connection = "dbname=${dbName}";
      timestamp_column_type = "timestamp with time zone";
      create_templates = [
        "CREATE TABLE {{ .table }} ({{ .columns }})"
        "SELECT create_hypertable({{ .table|quoteLiteral }}, by_range('time', INTERVAL '1 week'), if_not_exists := true)"
      ];
    };
  };
  services.postgresql = {
    enable = true;
    ensureDatabases = [ dbName ];
    ensureUsers = [
      {
        name = dbUser;
        ensureDBOwnership = true;
      }
    ];
    # Unemcumbered Apache-licensed version.
    extensions = ps: [ ps.timescaledb-apache ];
    settings.shared_preload_libraries = [ "timescaledb" ];
  };
}
