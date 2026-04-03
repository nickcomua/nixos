# Monitoring stack: Grafana + Prometheus + Loki + Promtail
# - Prometheus scrapes node_exporter (systemd service states) + comin exporter
# - Loki ingests journald logs via Promtail
# - Grafana available at http://grafana.local via nginx reverse proxy
{config, ...}: {
  # Local DNS: grafana.local → 127.0.0.1
  networking.hosts."127.0.0.1" = ["grafana.local"];

  # Nginx: reverse proxy for .local domains
  # Listens on all interfaces so other LAN devices (e.g. Mac) can reach it
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."grafana.local" = {
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
        proxyWebsockets = true;
      };
    };
  };

  # Allow HTTP through firewall for LAN access
  networking.firewall.allowedTCPPorts = [80];

  # Prometheus: metrics collection
  services = {
    prometheus = {
      enable = true;
      port = 9090;

      exporters.node = {
        enable = true;
        port = 9100;
        # systemd collector exposes per-unit active/inactive/failed state
        enabledCollectors = ["systemd"];
      };

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{targets = ["localhost:9100"];}];
        }
        {
          # comin exporter: deployment state, last apply time, errors
          # runs on port 4243 (comin default) when comin is active
          job_name = "comin";
          static_configs = [{targets = ["localhost:4243"];}];
        }
      ];
    };

    # Loki: log aggregation backend
    loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server.http_listen_port = 3100;
        common = {
          instance_addr = "127.0.0.1";
          path_prefix = "/var/lib/loki";
          storage.filesystem = {
            chunks_directory = "/var/lib/loki/chunks";
            rules_directory = "/var/lib/loki/rules";
          };
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
        };
        schema_config.configs = [
          {
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];
      };
    };

    # Promtail: ships journald logs → Loki
    promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 9080;
          grpc_listen_port = 0;
        };
        clients = [{url = "http://localhost:3100/loki/api/v1/push";}];
        scrape_configs = [
          {
            job_name = "journal";
            journal = {
              max_age = "12h";
              labels = {
                job = "systemd-journal";
                host = config.networking.hostName;
              };
            };
            relabel_configs = [
              # Expose systemd unit name as a label for filtering in Grafana
              {
                source_labels = ["__journal__systemd_unit"];
                target_label = "unit";
              }
              {
                source_labels = ["__journal__hostname"];
                target_label = "hostname";
              }
              {
                source_labels = ["__journal_priority_keyword"];
                target_label = "level";
              }
            ];
          }
        ];
      };
    };

    # Grafana: dashboard UI
    grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 3000;
          domain = "grafana.local";
          root_url = "http://grafana.local";
        };
        security.secret_key = "SW2YcwTIb9zpOOhoPsMm";
        "auth.anonymous" = {
          enabled = true;
          org_role = "Admin";
        };
        auth.disable_login_form = true;
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
            uid = "prometheus";
          }
          {
            name = "Loki";
            type = "loki";
            url = "http://localhost:3100";
            uid = "loki";
          }
        ];
      };
    };
  };
  # Port 80 opened in firewall for LAN access to grafana.local
}
