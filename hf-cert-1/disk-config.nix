{ config, ... }:
{
  disko.devices = {
    disk = {
      sda = {
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # EFI system partition
            biosBoot = {
              size = "1M";
              type = "EF02";
            };
            boot = {
              size = "256M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            swap = {
              size = "2G";
              content = {
                type = "swap";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
    };
    zpool.zroot = {
      type = "zpool";
      rootFsOptions = {
        compression = "lz4";
        "com.sun:auto-snapshot" = "true";
      };
      mountpoint = "/";
    };
  };

  services.zfs.autoScrub.enable = true;

  services.zfs.autoSnapshot = {
      enable = true;
      # -u uses UTC so there are not time change anomalies.
      flags = "-k -p --utc";
      frequent = 8; # the 15-minute snapshots
      hourly = 24 * 7;
      daily = 28;
      weekly = 8;
      monthly = 3;
   };

  # 90% of the total memory
  #
  # This server is 100% ZFS, so it makes sense to allow a huge zfs cache.
  boot.kernelParams = ["zfs.zfs_arc_max=${toString (config.hardware.systemMemory * 9 / 10)}"];

}
