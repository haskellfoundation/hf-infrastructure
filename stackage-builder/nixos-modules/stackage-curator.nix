{ pkgs, ... }:
{
  virtualisation.docker.enable = true;
  environment.systemPackages = with pkgs; [
    tmux
    git
    vim
    emacs
    wget
    jq
  ];
  programs.mosh.enable = true;
  users.mutableUsers = false;
  users.users = {
    curators = {
      description = "Stackage curators shared account";
      isNormalUser = true;
      createHome = true;
      extraGroups = [ "docker" ];
    };
  };
}
