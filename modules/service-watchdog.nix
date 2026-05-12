{ lib, pkgs, config, ... }:
let
  cfg = config.services.service-watchdog;
  watchdogOpts = { name, ... }: {
    options = {
      port = lib.mkOption {
        type = lib.types.port;
        description = "Port the service listens on";
      };
      endpoint = lib.mkOption {
        type = lib.types.str;
        description = "HTTP endpoint to check (e.g. /liveness)";
      };
      timeout = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Curl timeout in seconds";
      };
    };
  };
in {
  options.services.service-watchdog = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule watchdogOpts);
    default = {};
    description = "Watchdog health checks for services";
  };

  config = lib.mkIf (cfg != {}) {
    systemd.services = {
      # One template unit shared by all watchdogs. %i is the service name.
      "restarter@" = {
        description = "Restarter for %i after health check failure";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.systemd}/bin/systemctl restart %i.service";
        };
      };
    } // lib.concatMapAttrs (name: wcfg:
      let url = "http://localhost:${toString wcfg.port}${wcfg.endpoint}";
      in {
        "${name}-healthcheck" = {
          description = "Health check for ${name}";
          serviceConfig = {
            Type = "oneshot";
            DynamicUser = true;
          };
          script = ''
            if ${pkgs.curl}/bin/curl --fail-with-body --silent --show-error --max-time ${toString wcfg.timeout} "${url}" > /dev/null; then
              exit 0
            else
              STATUS=$?
              echo "${name} (${url}) health check failed with curl exit code $STATUS!"
              exit $STATUS
            fi
          '';
          onFailure = [ "restarter@${name}.service" ];
        };
      }) cfg;

    systemd.timers = lib.concatMapAttrs (name: wcfg: {
      "${name}-healthcheck" = {
        description = "Timer to periodically run health check for ${name}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          Unit = "${name}-healthcheck.service";
          OnBootSec = "1min";
          OnUnitActiveSec = "5min";
        };
      };
    }) cfg;
  };
}
