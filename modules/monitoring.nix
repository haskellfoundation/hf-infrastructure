{
  services.telegraf.enable = true;
  services.telegraf.extraConfig = {

    inputs = {
      # Interesting plugins:
      # - nstat (kernel network stats)
      # - smart (S.M.A.R.T.)
      # - zfs
      # - disk, diskio (maybe irrelevant with zfs)
      # - nginx (accepts, active, handled, reading, requests, waiting, writing)
      # - cpu
      # - linux_cpu (scaling and throttling)
      # - mem
      # - exec, execd (run a given command and read its output)
      # - net
      # - netstat
      # - socketstat (ss)
      # - wireguard
      # - postgresql
      #
      # Let's start with zfs, cpu, and mem
      cpu = {};
      mem = {};
      zfs = {};
    };

    outputs.discard = {};
  };
}
