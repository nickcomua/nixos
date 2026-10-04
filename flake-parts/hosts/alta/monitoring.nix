{
  config,
  pkgs,
  ...
}: let
  bwsServerUrl = "https://vault.bitwarden.eu";
  grafanaSecretIds = {
    secretKey = "22fa65f0-e0b8-4dee-ae9c-b4b300e38259";
    adminPassword = "42c14105-6a14-452b-86f8-b4b300e384e4";
  };

  fetchGrafanaSecret = pkgs.writeShellScript "fetch-grafana-bws-secret" ''
    set -euo pipefail

    secret_id="$1"
    destination="$2"
    tmp_json="$(${pkgs.coreutils}/bin/mktemp)"
    tmp_value="$(${pkgs.coreutils}/bin/mktemp)"
    trap '${pkgs.coreutils}/bin/rm -f "$tmp_json" "$tmp_value"' EXIT

    export BWS_ACCESS_TOKEN="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.BWS_ACCESS_TOKEN.path})"
    export BWS_SERVER_URL="${bwsServerUrl}"

    fetched=false
    for delay in 1 2 4 8 16; do
      if ${pkgs.bws}/bin/bws secret get "$secret_id" --output json >"$tmp_json"; then
        if ${pkgs.jq}/bin/jq --exit-status --raw-output \
          '.value | select(type == "string" and length > 0)' \
          "$tmp_json" >"$tmp_value"; then
          fetched=true
          break
        fi
      fi
      ${pkgs.coreutils}/bin/sleep "$delay"
    done

    if [[ "$fetched" != true ]]; then
      echo "Failed to fetch a non-empty Grafana secret from BWS" >&2
      exit 1
    fi

    ${pkgs.coreutils}/bin/install \
      --owner grafana \
      --group grafana \
      --mode 0400 \
      "$tmp_value" \
      "$destination"
  '';

  prepareGrafanaSecrets = pkgs.writeShellScript "prepare-grafana-secrets" ''
    set -euo pipefail
    ${fetchGrafanaSecret} ${grafanaSecretIds.secretKey} /run/grafana/secret-key
    ${fetchGrafanaSecret} ${grafanaSecretIds.adminPassword} /run/grafana/admin-password
  '';

  systemServiceLogsDashboard = pkgs.writeTextDir "system-service-logs.json" (builtins.toJSON {
    annotations.list = [];
    editable = false;
    fiscalYearStartMonth = 0;
    graphTooltip = 0;
    id = null;
    links = [];
    liveNow = false;
    panels = [
      {
        datasource = {
          type = "loki";
          uid = "loki";
        };
        gridPos = {
          h = 24;
          w = 24;
          x = 0;
          y = 0;
        };
        id = 1;
        options = {
          dedupStrategy = "none";
          enableLogDetails = true;
          prettifyLogMessage = false;
          showCommonLabels = false;
          showLabels = true;
          showTime = true;
          sortOrder = "Descending";
          wrapLogMessage = true;
        };
        targets = [
          {
            datasource = {
              type = "loki";
              uid = "loki";
            };
            editorMode = "code";
            expr = ''{source="systemd-journal", unit=~"$unit", level=~"$level"}'';
            queryType = "range";
            refId = "A";
          }
        ];
        title = "Journal logs";
        type = "logs";
      }
    ];
    refresh = "10s";
    schemaVersion = 41;
    tags = [
      "systemd"
      "journal"
      "loki"
    ];
    templating.list = [
      {
        allValue = ".*";
        current = {
          text = "All";
          value = "$__all";
        };
        datasource = {
          type = "loki";
          uid = "loki";
        };
        definition = ''label_values({source="systemd-journal"}, unit)'';
        includeAll = true;
        label = "Systemd unit";
        multi = true;
        name = "unit";
        options = [];
        query = ''label_values({source="systemd-journal"}, unit)'';
        refresh = 2;
        regex = "";
        skipUrlSync = false;
        sort = 1;
        type = "query";
      }
      {
        allValue = ".*";
        current = {
          text = "All";
          value = "$__all";
        };
        datasource = {
          type = "loki";
          uid = "loki";
        };
        definition = ''label_values({source="systemd-journal"}, level)'';
        includeAll = true;
        label = "Level";
        multi = true;
        name = "level";
        options = [];
        query = ''label_values({source="systemd-journal"}, level)'';
        refresh = 2;
        regex = "";
        skipUrlSync = false;
        sort = 1;
        type = "query";
      }
    ];
    time = {
      from = "now-24h";
      to = "now";
    };
    timepicker = {};
    timezone = "browser";
    title = "System Service Logs";
    uid = "system-service-logs";
    version = 1;
    weekStart = "";
  });
in {
  services = {
    prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9090;
      retentionTime = "30d";

      exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 9100;
        enabledCollectors = ["systemd"];
      };

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{targets = ["127.0.0.1:9100"];}];
        }
      ];
    };

    loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server = {
          http_listen_address = "127.0.0.1";
          http_listen_port = 3100;
          grpc_listen_address = "127.0.0.1";
        };
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
        compactor = {
          working_directory = "/var/lib/loki/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem";
        };
        limits_config.retention_period = "336h";
      };
    };

    alloy = {
      enable = true;
      configPath = "/etc/alloy/config.alloy";
      extraFlags = ["--disable-reporting"];
    };

    grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = 3000;
          domain = "alta.local";
          root_url = "http://alta.local:3000/";
        };
        security = {
          secret_key = "$__file{/run/grafana/secret-key}";
          admin_password = "$__file{/run/grafana/admin-password}";
        };
        "auth.anonymous".enabled = false;
      };
      provision = {
        enable = true;
        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "Alta system dashboards";
              options.path = systemServiceLogsDashboard;
              type = "file";
            }
          ];
        };
        datasources.settings = {
          apiVersion = 1;
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://127.0.0.1:9090";
              access = "proxy";
              isDefault = true;
              uid = "prometheus";
            }
            {
              name = "Loki";
              type = "loki";
              url = "http://127.0.0.1:3100";
              access = "proxy";
              uid = "loki";
            }
          ];
        };
      };
    };
  };

  networking.firewall.allowedTCPPorts = [3000];

  environment.etc."alloy/config.alloy".text = ''
    loki.write "local" {
      endpoint {
        url = "http://127.0.0.1:3100/loki/api/v1/push"
      }
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label = "unit"
      }

      // Messages emitted by systemd itself identify the affected service in
      // UNIT while _SYSTEMD_UNIT remains init.scope. Prefer UNIT when present
      // so lifecycle logs for quiet services are grouped with that service.
      rule {
        source_labels = ["__journal_unit"]
        regex         = "(.+)"
        target_label  = "unit"
      }

      rule {
        source_labels = ["__journal__hostname"]
        target_label = "hostname"
      }

      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label = "level"
      }

      rule {
        source_labels = ["__journal_syslog_identifier"]
        target_label = "syslog_identifier"
      }
    }

    loki.source.journal "system" {
      max_age       = "168h"
      relabel_rules = loki.relabel.journal.rules
      labels        = {
        host = "alta",
        source = "systemd-journal",
      }
      forward_to = [loki.write.local.receiver]
    }
  '';

  systemd.services = {
    alloy = {
      after = ["loki.service"];
      wants = ["loki.service"];
    };

    grafana = {
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig.ExecStartPre = ["+${prepareGrafanaSecrets}"];
    };
  };
}
