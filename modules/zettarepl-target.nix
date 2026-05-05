{ config, lib, pkgs, ... }:
let
  cfg = config.services.zettarepl-target;
in
{
  options.services.zettarepl-target = {
    enable = lib.mkEnableOption "zettarepl pull-based backup target";

    datasets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "ZFS datasets that the zettarepl user is allowed to send.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.zettarepl = {
      isNormalUser = true;
      description = "ZFS replication target user (pull-based backups)";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFEBM7InS0rUoRXkRaxpjBueVdDvFPPvD+4VZqSZFHVt"
      ];
    };

    system.activationScripts.zettarepl-zfs-allow = lib.stringAfter [ "users" ]
      (lib.concatMapStringsSep "\n" (ds: ''
        if ${pkgs.zfs}/bin/zfs list -o name -H ${lib.escapeShellArg ds} >/dev/null 2>&1; then
          ${pkgs.zfs}/bin/zfs allow zettarepl send,hold ${lib.escapeShellArg ds}
        else
          echo "zettarepl-target: dataset ${lib.escapeShellArg ds} does not exist, skipping"
        fi
      '') cfg.datasets);
  };
}
