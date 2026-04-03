# macOS monitoring stack: Grafana + Prometheus + Loki + Promtail
# Services run as launchd daemons (root-level), all bound to localhost
# Grafana available at http://grafana.local via /etc/hosts
{
  pkgs,
  config,
  ...
}: let
  prometheusConfig = pkgs.writeText "prometheus.yml" ''
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: node
        static_configs:
          - targets: ['localhost:9100']
      - job_name: comin
        # comin exporter runs on port 4243 when comin is active
        static_configs:
          - targets: ['localhost:4243']
  '';

  lokiConfig = pkgs.writeText "loki.yml" ''
    auth_enabled: false
    server:
      http_listen_port: 3100
    common:
      instance_addr: 127.0.0.1
      path_prefix: /var/lib/loki
      storage:
        filesystem:
          chunks_directory: /var/lib/loki/chunks
          rules_directory: /var/lib/loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory
    schema_config:
      configs:
        - from: 2024-01-01
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h
  '';

  promtailConfig = pkgs.writeText "promtail.yml" ''
    server:
      http_listen_port: 9080
      grpc_listen_port: 0
    clients:
      - url: http://localhost:3100/loki/api/v1/push
    scrape_configs:
      - job_name: varlogs
        static_configs:
          - targets: [localhost]
            labels:
              job: varlogs
              host: ${config.networking.hostName}
              __path__: /var/log/*.log
      - job_name: system_log
        static_configs:
          - targets: [localhost]
            labels:
              job: system_log
              host: ${config.networking.hostName}
              __path__: /var/log/system.log
  '';

  # Grafana provisioning lives in the Nix store — immutable and reproducible
  grafanaProvisioning = pkgs.runCommand "grafana-provisioning" {} ''
    mkdir -p $out/datasources
    cat > $out/datasources/default.yaml << 'EOF'
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://localhost:9090
        isDefault: true
        uid: prometheus
      - name: Loki
        type: loki
        url: http://localhost:3100
        uid: loki
    EOF
  '';

  # Nginx reverse proxy: grafana.local:80 → localhost:3000
  nginxConfig = pkgs.writeText "nginx-grafana.conf" ''
    daemon off;
    worker_processes 1;
    pid /var/run/nginx-grafana.pid;
    error_log /var/log/nginx-grafana-error.log;
    events { worker_connections 128; }
    http {
      access_log /var/log/nginx-grafana-access.log;
      server {
        listen 127.0.0.1:80;
        server_name grafana.local;
        location / {
          proxy_pass http://127.0.0.1:3000;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        }
      }
    }
  '';

  grafanaConfig = pkgs.writeText "grafana.ini" ''
    [server]
    http_addr = 127.0.0.1
    http_port = 3000
    domain = grafana.local
    root_url = http://grafana.local

    [auth.anonymous]
    enabled = true
    org_role = Admin

    [paths]
    data = /var/lib/grafana
    logs = /var/log/grafana
    plugins = /var/lib/grafana/plugins
    provisioning = ${grafanaProvisioning}
  '';
in {
  # Local DNS: grafana.local → 127.0.0.1
  environment.etc."hosts" = {
    text = ''
      ##
      # Host Database
      ##
      127.0.0.1	localhost
      255.255.255.255	broadcasthost
      ::1             localhost
      127.0.0.1	grafana.local
    '';
  };

  # node_exporter via native nix-darwin module (handles launchd setup automatically)
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    listenAddress = "127.0.0.1";
    # macOS: no systemd collector available
    extraFlags = ["--no-collector.systemd"];
  };

  # Create required data directories at activation time
  system.activationScripts.monitoring-dirs = {
    text = ''
      mkdir -p /var/lib/prometheus
      mkdir -p /var/lib/loki/chunks /var/lib/loki/rules
      mkdir -p /var/lib/grafana/plugins
      mkdir -p /var/log/grafana
      mkdir -p /var/tmp/nginx-grafana
    '';
  };

  launchd.daemons = {
    # Nginx: reverse proxy so http://grafana.local (port 80) works
    nginx-grafana = {
      serviceConfig = {
        Label = "org.nginx.grafana-proxy";
        ProgramArguments = [
          "${pkgs.nginx}/bin/nginx"
          "-c"
          "${nginxConfig}"
          "-p"
          "/var/tmp/nginx-grafana"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/nginx-grafana.log";
        StandardErrorPath = "/var/log/nginx-grafana.log";
      };
    };

    prometheus = {
      serviceConfig = {
        Label = "org.prometheus.server";
        ProgramArguments = [
          "${pkgs.prometheus}/bin/prometheus"
          "--config.file=${prometheusConfig}"
          "--storage.tsdb.path=/var/lib/prometheus"
          "--web.listen-address=127.0.0.1:9090"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/prometheus.log";
        StandardErrorPath = "/var/log/prometheus.log";
      };
    };

    loki = {
      serviceConfig = {
        Label = "org.grafana.loki";
        ProgramArguments = [
          "${pkgs.grafana-loki}/bin/loki"
          "-config.file=${lokiConfig}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/loki.log";
        StandardErrorPath = "/var/log/loki.log";
      };
    };

    promtail = {
      serviceConfig = {
        Label = "org.grafana.promtail";
        ProgramArguments = [
          "${pkgs.grafana-loki}/bin/promtail"
          "-config.file=${promtailConfig}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/promtail.log";
        StandardErrorPath = "/var/log/promtail.log";
      };
    };

    grafana = {
      serviceConfig = {
        Label = "org.grafana.grafana";
        ProgramArguments = [
          "${pkgs.grafana}/bin/grafana"
          "server"
          "--homepath=${pkgs.grafana}/share/grafana"
          "--config=${grafanaConfig}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/grafana/grafana.log";
        StandardErrorPath = "/var/log/grafana/grafana.log";
      };
    };
  };
}
