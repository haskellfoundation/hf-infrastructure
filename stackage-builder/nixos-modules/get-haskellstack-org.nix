# Defines get-haskellstack-org.service, which serves the redirects in
# commercialhaskell/get-haskellstack-org, and get-haskellstack-org-refresh.timer,
# its fallback for missed webhook deliveries.
{ lib, pkgs, config, ... }:
let
  cfg = config.services.get-haskellstack-org;
  name = "get-haskellstack-org";
  port = toString cfg.port;
  secret = "${name}/webhook-secret";
in {
  options.services.get-haskellstack-org = {
    enable = lib.mkEnableOption "the get.haskellstack.org redirect server";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The get-haskellstack-org package";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3003;
      description = "Loopback port the server listens on";
    };

    virtualHost = lib.mkOption {
      type = lib.types.str;
      example = "get.haskellstack.org";
      description = "Caddy site address the server is reachable at";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${secret} = {};

    systemd.services.${name} = {
      description = "get.haskellstack.org redirect server";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment.PORT = port;
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/get-haskellstack-org";
        DynamicUser = true;
        LoadCredential = "webhook-secret:${config.sops.secrets.${secret}.path}";
        # Startup fails while GitHub is unreachable; keep retrying, slowly
        # enough never to hit the start limit.
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    systemd.services."${name}-refresh" = {
      description = "Ask get-haskellstack-org to reload its redirects";
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        # A direct request, with no X-Forwarded-For, needs no signature.
        ExecStart = "${pkgs.curl}/bin/curl --fail --silent --show-error -X POST http://127.0.0.1:${port}/_refresh";
      };
    };

    systemd.timers."${name}-refresh" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/15";
        RandomizedDelaySec = 60;
      };
    };

    services.caddy.enable = true;
    services.caddy.virtualHosts.${cfg.virtualHost}.extraConfig = ''
      reverse_proxy 127.0.0.1:${port}
    '';
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
