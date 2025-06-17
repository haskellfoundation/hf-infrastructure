{ config, ... }: {
  imports =
    [
      ./hardware-configuration.nix
      ./disk-config.nix
    ];

  services.haskell-certification = {
    enable = true;
    environmentFile = config.sops.secrets.cert_env_file.path;
    externalUri = "https://certification.haskell.foundation";
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
  services.caddy.virtualHosts."certification.haskell.foundation" = {
    extraConfig = ''
      reverse_proxy :3000
    '';
  };
  # Preserve the legacy redirect from the original URL
  services.caddy.virtualHosts."certification.serokell.io" = {
    extraConfig = ''
      redir https://certification.haskell.foundation{uri} permanent
    '';
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  system.stateVersion = "24.05";
}
