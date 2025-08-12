{ config, lib, ... }:
{
  options = {
    hardware.systemMemory = lib.mkOption {
      type = lib.types.int;
      description = "Total system memory in bytes, used to calculate journald size.";
    };
  };

  config = {
    # Default is 100. Wtf, NixOS?
    boot.loader.grub.configurationLimit = 20;

    networking.domain = "haskell.foundation";

    nix = {
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
      optimise = {
        automatic = true;
        dates = [
          "monthly"
        ];
      };
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        substituters = [
          "https://cache.nixos.org"
          "https://stackage-infrastructure.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "stackage-infrastructure.cachix.org-1:R3E1FYE8IKCNbUWCvVhsnlLJ4FC6onEQLhQX2kY0ufQ="
        ];
        always-allow-substitutes = true;
      };
    };

    security.acme.acceptTerms = true;

    services.fail2ban.enable = true;
    services.fwupd.enable = true;
    services.journald.extraConfig =
      let
        # Bump to 20%, a little bigger than the default 10%
        maxJournald = toString (config.hardware.systemMemory * 2 / 10);
      in "SystemMaxSize=${maxJournald}";

    services.openssh.enable = true;
    services.openssh.settings.PasswordAuthentication = false;
    services.openssh.startWhenNeeded = true;
  };
}
