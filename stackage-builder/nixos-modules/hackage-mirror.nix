{ hackage-mirror-tool-app }:
{ lib, ... }:
let
  name = "hackage-mirror";
in {
  sops.secrets = {
    "${name}/access_key_fpco" = {};
    "${name}/secret_fpco" = {};
    "${name}/access_key_r2" = {};
    "${name}/secret_r2" = {};
    "${name}/r2_endpoint" = {
      key = "stackage-server/r2_endpoint";
    };
  };
  users.groups.${name} = {
    gid = 1004;
  };
  users.users.${name} = {
    uid = 1004;
    isNormalUser = true;
    group = name;
    home = "/home/${name}";
    createHome = true;
  };
  systemd.services.${name} = {
    description = "Stackage Hackage mirror updater";
    serviceConfig = {
      User = name;
      LoadCredential = "creds:/run/secrets/${name}";
      Type = "oneshot";
      WorkingDirectory = "~";
    };
    script = ''
      echo "OLD BUCKET"

      export S3_ACCESS_KEY="$(< "$CREDENTIALS_DIRECTORY/creds_access_key_fpco")"
      export S3_SECRET_KEY="$(< "$CREDENTIALS_DIRECTORY/creds_secret_fpco")"
      ${lib.getExe hackage-mirror-tool-app} \
          --s3-base-url      s3.amazonaws.com \
          --s3-bucket-id     "hackage.fpcomplete.com" \
          --max-connections  10

      echo "NEW BUCKET"

      export S3_ACCESS_KEY="$(< "$CREDENTIALS_DIRECTORY/creds_access_key_r2")"
      export S3_SECRET_KEY="$(< "$CREDENTIALS_DIRECTORY/creds_secret_r2")"
      ${lib.getExe hackage-mirror-tool-app} \
          --s3-base-url      "$(< "$CREDENTIALS_DIRECTORY/creds_r2_endpoint")" \
          --s3-bucket-id     "hackage-mirror" \
          --max-connections  10
    '';
  };
  systemd.timers.${name} = {
    description = "Fires ${name}.service";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      Unit = "${name}.service";
      OnBootSec = 30;
      # Only fire if the previous run has finished.
      OnUnitInactiveSec = "5 min";
    };
  };
}

