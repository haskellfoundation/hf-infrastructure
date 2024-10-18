let
  # From `free -b`
  mem = 8133238784;
  hostName = "hf-cert-1";
  hostId = "57de31ac"; # head -c4 /dev/urandom | od -A none -t x4

in
{ config, ... }: {
  imports =
    [
      ./hardware-configuration.nix
      (import ./disk-config.nix { systemMemory = mem; })
      (import ../system-common.nix { inherit hostName mem hostId; })
    ];

  services.haskell-certification = {
    enable = true;
    environmentFile = config.sops.secrets.cert_env_file.path;
    externalUri = "https://new-certification.haskell.foundation";
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ "haskell-certification" ];
    ensureUsers = [
      {
        name = "haskell-certification";
        ensureDBOwnership = true;
      }
    ];
  };

  services.caddy.enable = true;
  services.caddy.virtualHosts."new-certification.haskell.foundation" = {
    extraConfig = ''
      reverse_proxy :3000
    '';
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
