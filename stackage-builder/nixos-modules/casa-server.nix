{ casa-uid, casa-updater-uid, casa-app, curator-app }: { lib, pkgs, config, ... }:
let
  name = "casa";
  updateName = "casa-update";
  vhostStackageOrg = "casa.stackage.org";
  publicPort = 3001;
  privatePushPort = 3002;
in {
  # casa server
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
  sops.secrets = {
    "stackage.org/cloudflare-origin-cert" =
      { owner = config.services.nginx.user; };
    "stackage.org/cloudflare-origin-cert-private-key" =
      { owner = config.services.nginx.user; };
  };
  users.groups.${name} = {
    gid = casa-uid;
  };
  users.users.${name} = {
    uid = casa-uid;
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
      # RTS flags copied from FPCo deployment.
      ${casa-app}/bin/casa-server +RTS -I3 -N1
    '';
  };
  services.nginx.enable = true;
  services.nginx.virtualHosts = {
    ${vhostStackageOrg} = {
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString publicPort}";
        recommendedProxySettings = true;
      };
      sslCertificate = "/run/secrets/stackage.org/cloudflare-origin-cert";
      sslCertificateKey = "/run/secrets/stackage.org/cloudflare-origin-cert-private-key";
    };
  };
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # casa-update
  users.groups.${updateName} = {
    gid = casa-updater-uid;
  };
  users.users.${updateName} = {
    uid = casa-updater-uid;
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
      ${curator-app}/bin/casa-curator \
        continuous-populate-push \
        --reset-push \
        --sleep-for 15 \
        --sqlite-file ./db.sqlite \
        --download-concurrency 10 \
        --push-url http://localhost:${toString privatePushPort} \
        --pull-url  http://localhost:${toString publicPort}
    '';
  };
}
