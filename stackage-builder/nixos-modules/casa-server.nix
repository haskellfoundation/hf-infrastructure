{ lib, pkgs, config, ... }:
let
  cfg = config.services.casa;
  name = "casa";
  updateName = "casa-update";
  vhostStackageOrg = "casa.stackage.org";
  publicPort = 3001;
  privatePushPort = 3002;
in {
  options.services.casa = {
    enable = lib.mkEnableOption "Casa content-addressable storage server";

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1007;
      description = "UID for the casa user";
    };

    updaterUid = lib.mkOption {
      type = lib.types.int;
      default = 1008;
      description = "UID for the casa-update user";
    };

    package = lib.mkOption {
      type = lib.types.package;
      description = "The casa-server package";
    };

    curatorPackage = lib.mkOption {
      type = lib.types.package;
      description = "The curator package (provides casa-curator)";
    };

    tls = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TLS with Cloudflare origin certificates";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "casa" ];
      ensureUsers = [
        {
          name = "casa";
          ensureDBOwnership = true;
        }
      ];
    };
    # FIXME: Start using origin domain + certbot rather than an origin cert.
    sops.secrets = lib.mkIf cfg.tls.enable {
      "stackage.org/cloudflare-origin-cert" =
        { owner = config.services.nginx.user; };
      "stackage.org/cloudflare-origin-cert-private-key" =
        { owner = config.services.nginx.user; };
    };
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
    systemd.services.${name} = {
      description = "Casa server";
      wants = [ "postgresql.service" "network.target" ];
      after = [ "postgresql.service" "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = name;
        Restart = "on-failure";
        RestartSec = 1;
        WorkingDirectory = "~";
      };
      environment = {
        DBCONN = "postgresql://casa@/casa";
        PORT = toString publicPort;
        AUTHORIZED_PORT = toString privatePushPort;
      };
      script = ''
        # Previously we had -N1, copied from the old deployment. It seemed to be
        # working fine, so I'll just bump it a little bit to be on the safe side
        # (cf. the similar change to stackage-server).
        #
        # The process had 1.2G resident when I checked.
        ${cfg.package}/bin/casa-server +RTS -N10 -H2G
      '';
    };
    services.nginx.enable = true;
    services.nginx.virtualHosts = {
      ${vhostStackageOrg} = {
        forceSSL = cfg.tls.enable;
        locations."/" = {
          # casa-server only speaks ipv4 right now.
          proxyPass = "http://127.0.0.1:${toString publicPort}";
          recommendedProxySettings = true;
        };
      } // lib.optionalAttrs cfg.tls.enable {
        # FIXME: Start using origin domain + certbot rather than an origin cert.
        sslCertificate = "/run/secrets/stackage.org/cloudflare-origin-cert";
        sslCertificateKey = "/run/secrets/stackage.org/cloudflare-origin-cert-private-key";
      };
    };
    networking.firewall.allowedTCPPorts = [ 22 80 443 ];

    # casa-update
    users.groups.${updateName} = {
      gid = cfg.updaterUid;
    };
    users.users.${updateName} = {
      uid = cfg.updaterUid;
      isNormalUser = true;
      group = name;
      home = "/home/${updateName}";
      createHome = true;
    };
    systemd.services.${updateName} = {
      description = "Casa updater";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = updateName;
        Restart = "on-failure";
        RestartSec = 1;
        WorkingDirectory = "~";
      };
      script = ''
        ${cfg.curatorPackage}/bin/casa-curator \
          continuous-populate-push \
          --reset-push \
          --sleep-for 15 \
          --sqlite-file ./db.sqlite \
          --download-concurrency 10 \
          --push-url http://localhost:${toString privatePushPort} \
          --pull-url  http://localhost:${toString publicPort}
      '';
    };
  };
}
