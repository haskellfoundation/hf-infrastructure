{ hostName, hostId, mem}:
let
  # Bump to 20%, a little bigger than the default 10%
  maxJournald = totalMem: totalMem * 2 / 10;
in
{
  networking.hostName = hostName;
  networking.domain = "haskell.foundation";
  networking.hostId = hostId;

  services.journald.extraConfig = "SystemMaxSize=${toString (maxJournald mem)}";

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.startWhenNeeded = true;
  services.fail2ban.enable = true;
  services.fwupd.enable = true;
}
