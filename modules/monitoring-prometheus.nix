{ config, lib, pkgs, ... }:
let
  nodeExporterPort = 9100;
  prometheusPort = 9090;
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
    } > "$out"
    mv "$out" "$final"
  '';
in
{
  services.prometheus = {
    enable = true;
    port = prometheusPort;
    retentionTime = "90d";
    scrapeConfigs = [
      {
        job_name = "node";
        scrape_interval = "15s";
        static_configs = [
          { targets = [ "localhost:${toString nodeExporterPort}" ]; }
        ];
      }
    ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    port = nodeExporterPort;
    enabledCollectors = [ "textfile" ];
    extraFlags = [
      "--collector.textfile.directory=${textfileDir}"
    ];
  };

  # Directory for textfile collector metrics
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

  services.grafana = {
    enable = true;
    settings.server.http_port = 8600;
    settings."auth.anonymous".enabled = true;

    provision = {
      enable = true;
      datasources = {
        settings = {
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://localhost:${toString prometheusPort}";
              isDefault = true;
            }
          ];
        };
      };
    };
  };
}
