{ config, lib, pkgs, ... }:
let
  nodeExporterPort = 9100;
  zfsExporterPort = 9134;
  prometheusPort = 9090;
in
{
  imports = [ ./zfs-dataset-metrics.nix ];

  services.prometheus = {
    enable = true;
    port = prometheusPort;
    retentionTime = "90d";
    scrapeConfigs = [
      {
        job_name = "node";
        scrape_interval = "15s";
        static_configs = [
          { targets = [
            "localhost:${toString nodeExporterPort}"
            "localhost:${toString zfsExporterPort}"
          ]; }
        ];
      }
    ];
  };

  services.prometheus.exporters.node = {
    port = nodeExporterPort;
  };

  services.prometheus.exporters.zfs = {
    enable = true;
    port = zfsExporterPort;
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
