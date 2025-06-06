# Defines stackage.service, stackage-update.service, and stackage-update.timer.
# Also includes a health check and auto-restart mechanism for stackage.service.
#
# stackage-update.service runs stackage-server-cron to keep the Stackage website
# up to date.
#
# TODO: As a sort-of experiment, I mixed sops-nix with systemd's LoadCredential
# functionality. I am not sure this was a good idea and would love to have
# someone else comment on it.
#
# Pros:
# * Systemd manages ownership
# * The whole directory of secrets gets passed to the unit
# * It would work with ephemeral users if I used such a thing
#
# Cons:
# * Since sops works at the level of individual secrets, I can't use
#   config.sops.secrets.${secret??}.path if I want to pass the whole directory.
#   The directory is an implementation detail of the name of the secret. So I
#   have to use the literal /run/secrets/, which leaks an implementation detail
#   of sops-nix.
#
#
{ stackage-update-uid, stackage-uid, stackage-server-app }: { pkgs, config, lib, ... }:
let
  srvName = "stackage-server";
  updateName = "stackage-update";
  restarterName = "stackage-restarter";
  stackagePort = 3000;
  mkService =
    { description ? "Stackage server"
    , workDir ? "~"
    , keyName ? "creds_aws_access_fpco"
    , secretName ? "creds_aws_secret_fpco"
    , extraEnvironment ? {}
    , script ? null
    }:
    {
      inherit description;
      wants = [ "postgresql.service" "network.target" ];
      after = [ "postgresql.service" "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = srvName;
        Restart = "on-failure";
        RestartSec = 1;
        LoadCredential = "creds:/run/secrets/${srvName}";
        WorkingDirectory = workDir;
        # If stackage-server supports it, Type=notify and WatchdogSec=30s would be ideal.
        # Since it likely doesn't, we use an external timer-based check.
      };
      path = [ pkgs.git ];
      environment = {
        PGSTRING = "postgresql://stackage@/stackage";
      } // extraEnvironment;
      preStart = ''
        ln -srf ${stackage-server-app}/run/* .
      '';
      script = if script == null then ''
        # FIXME: Does stackage-server even use these creds?
        export AWS_ACCESS_KEY_ID="$(< "$CREDENTIALS_DIRECTORY/${keyName}")"
        export AWS_SECRET_ACCESS_KEY="$(< "$CREDENTIALS_DIRECTORY/${secretName}")"

        # FIXME: RTS flags copied from FPCo deployment. Maybe not suitable
        # for ours. Note also the server is never idle for 3 seconds, so -I3
        # basically just turns off the idle GC.
        ${stackage-server-app}/bin/stackage-server +RTS -I3 -N1
      '' else script;
    };
in {
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "stackage" ];
    # The following three settings allow both services, running as their
    # own system users, to connect to the db as dbuser "stackage".
    ensureUsers = [
      {
        name = "stackage";
        ensureDBOwnership = true;
      }
    ];
    identMap = ''
      stackage_users ${srvName} stackage
      stackage_users ${updateName} stackage
    '';
    authentication = ''
      local stackage stackage peer map=stackage_users
    '';
  };
  sops.secrets = {
    "${srvName}/aws_access_fpco" = {};
    "${srvName}/aws_secret_fpco" = {};
    "${srvName}/aws_access_r2" = {};
    "${srvName}/aws_secret_r2" = {};
    "${srvName}/r2_endpoint" = {};
    "stackage.org/cloudflare-origin-cert" =
      { owner = config.services.nginx.user; };
    "stackage.org/cloudflare-origin-cert-private-key" =
      { owner = config.services.nginx.user; };
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
  };

  # STACKAGE SERVER

  users.groups.${srvName} = {
    gid = stackage-uid;
  };
  users.users.${srvName} = {
    uid = stackage-uid;
    isNormalUser = true;
    group = srvName;
    home = "/home/${srvName}";
    createHome = true;
  };
  systemd.services."${srvName}" = mkService {
    keyName = "creds_aws_access_r2";
    secretName = "creds_aws_secret_r2";
    extraEnvironment = {
      DOWNLOAD_BUCKET_URL = "https://stackage-haddock.haskell.org";
    };
  };

  services.nginx.virtualHosts =
    let
      stackageProxy = { port }: {
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString port}";
          recommendedProxySettings = true;
        };
      };
    in {
      "www.stackage.org" = (stackageProxy { port = stackagePort; }) // {
        sslCertificate = "/run/secrets/stackage.org/cloudflare-origin-cert";
        sslCertificateKey = "/run/secrets/stackage.org/cloudflare-origin-cert-private-key";
      };
    };
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # HEALTH CHECK AND AUTO-RESTART MECHANISM FOR STACKAGE SERVER

  systemd.services."${srvName}-healthcheck" = {
    description = "Health check for ${srvName}";
    serviceConfig = {
      Type = "oneshot";
      User = "nobody";
      Group = "nogroup";
    };
    script = ''
      # 10 second timeout for potentially slow first responses.
      if ${pkgs.curl}/bin/curl --location --fail-with-body --silent --show-error --max-time 10 "http://localhost:${toString stackagePort}/lts" > /dev/null; then
        exit 0
      else
        STATUS=$?
        echo "${srvName} (http://localhost:${toString stackagePort}/) health check failed with curl exit code $STATUS!"
        exit $STATUS
      fi
    '';
    # If this health check service fails, trigger the restarter service.
    onFailure = [ "${restarterName}.service" ];
  };

  systemd.services."${restarterName}" = {
    description = "Restarter for ${srvName} after health check failure";
    serviceConfig = {
      Type = "oneshot";
      # This service runs as root by default (since no User= is specified),
      # which has the necessary permissions to restart other services.
    };
    script = ''
      echo "Attempting to restart ${srvName}.service due to a failed health check."
      ${pkgs.systemd}/bin/systemctl restart ${srvName}.service
    '';
  };

  systemd.timers."${srvName}-healthcheck" = {
    description = "Timer to periodically run health check for ${srvName}";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      Unit = "${srvName}-healthcheck.service";
      OnBootSec = "1min";
      OnUnitActiveSec = "5min"; # Check every 5 minutes
    };
  };

  # STACKAGE UPDATER

  users.groups.${updateName} = {
    gid = stackage-update-uid;
  };
  users.users.${updateName} = {
    uid = stackage-update-uid;
    isNormalUser = true;
    group = updateName;
    home = "/home/${updateName}";
    createHome = true;
  };
  systemd.services.${updateName} = {
    description = "Stackage server updater";
    serviceConfig = {
      User = updateName;
      WorkingDirectory = "~";
      LoadCredential = "creds:/run/secrets/${srvName}";
      Type = "oneshot";
    };
    path = [ pkgs.git ];
    environment = {
      # This access is enabled in the services.postgres section
      PGSTRING = "postgresql://stackage@/stackage";
    };
    preStart = ''
      ln -srf ${stackage-server-app}/run/config $HOME
    '';
    script = ''
      # FIXME: This stack update is a cargo cult from the fpco k8s
      # deployment. I don't know what it's for.
      ${pkgs.stack}/bin/stack update

      export AWS_ACCESS_KEY_ID="$(< "$CREDENTIALS_DIRECTORY/creds_aws_access_r2")"
      export AWS_SECRET_ACCESS_KEY="$(< "$CREDENTIALS_DIRECTORY/creds_aws_secret_r2")"
      export AWS_S3_ENDPOINT="$(< "$CREDENTIALS_DIRECTORY/creds_r2_endpoint")"

      ${stackage-server-app}/bin/stackage-server-cron \
        --cache-cabal-files --log-level info \
        --download-bucket stackage-haddock \
        --upload-bucket stackage-haddock \
        --download-bucket-url https://stackage-haddock.haskell.org
    '';
  };
  systemd.timers.${updateName} = {
    description = "${updateName} trigger";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      Unit = "${updateName}.service";
      OnBootSec = 30;
      # Only fire if the previous run has finished.
      OnUnitInactiveSec = "5 min";
    };
  };
}
