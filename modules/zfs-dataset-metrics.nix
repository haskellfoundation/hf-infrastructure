{ pkgs, ... }:
let
  textfileDir = "/run/prometheus-node-exporter-textfiles";

  # Reads per-dataset I/O stats from /proc/spl/kstat/zfs and writes them
  # in Prometheus textfile format. node_exporter picks these up via the
  # textfile collector.
  zfsDatasetMetrics = pkgs.writeShellScript "zfs-dataset-metrics" ''
    set -euo pipefail
    out="${textfileDir}/zfs_dataset.prom.$$"
    final="${textfileDir}/zfs_dataset.prom"

    {
      echo "# HELP zfs_dataset_nread_bytes_total Bytes read from ZFS dataset"
      echo "# TYPE zfs_dataset_nread_bytes_total counter"
      echo "# HELP zfs_dataset_nwritten_bytes_total Bytes written to ZFS dataset"
      echo "# TYPE zfs_dataset_nwritten_bytes_total counter"

      for objset in /proc/spl/kstat/zfs/*/objset-*; do
        dataset=""
        nread=""
        nwritten=""
        while IFS=' ' read -r key _ value; do
          case "$key" in
            dataset_name) dataset="$value" ;;
            nread) nread="$value" ;;
            nwritten) nwritten="$value" ;;
          esac
        done < "$objset"
        if [ -n "$dataset" ] && [ -n "$nread" ] && [ -n "$nwritten" ]; then
          echo "zfs_dataset_nread_bytes_total{dataset=\"$dataset\"} $nread"
          echo "zfs_dataset_nwritten_bytes_total{dataset=\"$dataset\"} $nwritten"
        fi
      done

      # Per-dataset usage from zfs list
      echo "# HELP zfs_dataset_refer_bytes Direct usage (REFER) of ZFS dataset"
      echo "# TYPE zfs_dataset_refer_bytes gauge"
      echo "# HELP zfs_dataset_snapshot_bytes Snapshot usage (USED minus REFER) of ZFS dataset"
      echo "# TYPE zfs_dataset_snapshot_bytes gauge"
      echo "# HELP zfs_dataset_avail_bytes Available space in ZFS dataset"
      echo "# TYPE zfs_dataset_avail_bytes gauge"

      ${pkgs.zfs}/bin/zfs list -Hp -o name,used,avail,refer | while IFS=$'\t' read -r name used avail refer; do
        snapshot=$(( used - refer ))
        echo "zfs_dataset_refer_bytes{dataset=\"$name\"} $refer"
        echo "zfs_dataset_snapshot_bytes{dataset=\"$name\"} $snapshot"
        echo "zfs_dataset_avail_bytes{dataset=\"$name\"} $avail"
      done
    } > "$out"
    mv "$out" "$final"
  '';
in
{
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "textfile" ];
    extraFlags = [
      "--collector.textfile.directory=${textfileDir}"
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
  ];

  # Collect ZFS per-dataset I/O stats every 15 seconds
  systemd.services.zfs-dataset-metrics = {
    description = "Collect ZFS per-dataset I/O metrics for Prometheus";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = zfsDatasetMetrics;
    };
  };
  systemd.timers.zfs-dataset-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:*:0/15";
      AccuracySec = "1s";
    };
  };
}
