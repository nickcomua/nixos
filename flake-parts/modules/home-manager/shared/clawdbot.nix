# Shared OpenClaw configuration for all hosts (macOS + NixOS)
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.programs.openclaw;

  # Platform detection
  inherit (pkgs.stdenv) isLinux;
  inherit (pkgs.stdenv) isDarwin;

  inherit (pkgs.stdenv.hostPlatform) system;
  openclawPkgs = inputs.nix-openclaw.packages.${system};

  homeDir = config.home.homeDirectory;
  secretsDir = "${homeDir}/.secrets";

  # Placeholder tokens - will be substituted by activation script after sops decryption
  openclawHooksTokenPlaceholder = "__SOPS_OPENCLAW_HOOKS_TOKEN__";
  gmailPushTokenPlaceholder = "__SOPS_GMAIL_PUSH_TOKEN__";

  # Whisper transcription script (shared with NixOS module)
  whisperTranscribe = import ../../_programs/whisper-transcribe/package.nix {inherit pkgs lib;};

  # macOS-only tools that must be excluded on Linux
  macOSOnlyTools = [
    "peekaboo" # macOS screenshot tool
    "bird" # X/Twitter CLI (macOS binary only)
    "imsg" # iMessage (macOS only)
    "poltergeist" # File watcher (no Linux binary)
  ];

  # Base tools to exclude on all platforms
  baseExcludeTools = [
    "git-jump" # Conflicts with git package
  ];

  # Platform-specific excludeTools
  excludeTools = baseExcludeTools ++ (lib.optionals isLinux macOSOnlyTools);
in {
  imports = [
    inputs.nix-openclaw.homeManagerModules.openclaw
  ];

  config = lib.mkIf cfg.enable {
    home = {
      # Force overwrite openclaw.json to avoid .bak conflicts
      file.".openclaw/openclaw.json".force = true;

      # macOS-only: OpenClaw desktop app
      packages = lib.optionals isDarwin [
        openclawPkgs.openclaw-app
      ];

      # Activation script to substitute placeholder tokens with real secrets
      # Runs after sops decrypts secrets and after openclaw config is generated
      activation.substituteOpenclawSecrets = lib.mkIf isLinux (
        lib.hm.dag.entryAfter ["writeBoundary" "sops-nix"] ''
          configFile="${homeDir}/.openclaw/openclaw.json"
          if [ -f "$configFile" ]; then
            # Read secrets from sops-decrypted paths
            hooksToken=$(cat ${config.sops.secrets."openclaw-hooks-token".path} 2>/dev/null || echo "")
            pushToken=$(cat ${config.sops.secrets."gmail-push-token".path} 2>/dev/null || echo "")

            if [ -n "$hooksToken" ] && [ -n "$pushToken" ]; then
              # Substitute placeholders with real values
              ${pkgs.gnused}/bin/sed -i \
                -e "s|${openclawHooksTokenPlaceholder}|$hooksToken|g" \
                -e "s|${gmailPushTokenPlaceholder}|$pushToken|g" \
                "$configFile"
              echo "Substituted openclaw secrets in config"
            else
              echo "Warning: Could not read sops secrets for openclaw"
            fi
          fi
        ''
      );
    };

    # Load ANTHROPIC_API_KEY env var for the openclaw gateway service
    # The secrets file must be in KEY=value format for systemd EnvironmentFile
    systemd.user.services.openclaw-gateway.Service.EnvironmentFile =
      lib.mkIf isLinux "${secretsDir}/openclaw-env";

    # Sops secrets configuration (Linux only - decrypted at activation time)
    sops = lib.mkIf isLinux {
      defaultSopsFile = ../../../../secrets.yaml;
      age.keyFile = "${homeDir}/.config/sops/age/keys.txt";
      secrets = {
        "openclaw-hooks-token" = {};
        "gmail-push-token" = {};
      };
    };

    programs.openclaw = {
      package = openclawPkgs.openclaw;
      appPackage = lib.mkIf isDarwin openclawPkgs.openclaw-app;
      inherit excludeTools;

      instances.default = {
        enable = true;
        package = openclawPkgs.openclaw-gateway;

        config = {
          gateway.mode = "local";

          # Secrets provider for env-based secrets
          secrets.providers.local = {
            source = "env";
            allowlist = ["ANTHROPIC_API_KEY"];
          };

          # Telegram channel
          channels.telegram.accounts.default = {
            tokenFile = "${secretsDir}/telegram-bot-token";
            allowFrom = [527580149];
            groups."*" = {
              requireMention = true;
            };
            capabilities = ["elevated"];
          };

          # Anthropic provider — API key loaded via ANTHROPIC_API_KEY env var
          # The env var is set by the systemd service EnvironmentFile
          models.providers.anthropic = {
            api = "anthropic-messages";
            baseUrl = "https://api.anthropic.com";
            apiKey = {
              source = "env";
              provider = "local";
              id = "ANTHROPIC_API_KEY";
            };
            models = [
              {
                id = "claude-opus-4-6";
                name = "Claude Opus 4.6";
              }
              {
                id = "claude-sonnet-4-6";
                name = "Claude Sonnet 4.6";
              }
            ];
          };

          # Browser - OpenClaw managed profile with Google Chrome
          browser = {
            enabled = true;
            defaultProfile = "openclaw";
            executablePath = "${
              if isLinux
              then "/run/current-system/sw/bin/google-chrome"
              else "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            }";
          };

          # Elevated mode for running commands with sudo
          tools.elevated = {
            enabled = true;
            allowFrom."*" = [527580149];
          };

          # Gmail PubSub hooks (real-time email notifications)
          # Token values are placeholders - substituted by activation script after sops decryption
          hooks = {
            enabled = true;
            path = "/hooks";
            token = openclawHooksTokenPlaceholder;
            presets = ["gmail"];
            gmail = {
              account = "mykola.korniichuk.ua@gmail.com";
              label = "INBOX";
              topic = "projects/ultra-might-484613-t0/topics/gog-gmail-watch";
              subscription = "gog-gmail-watch-push";
              pushToken = gmailPushTokenPlaceholder;
              hookUrl = "http://127.0.0.1:18789/hooks/gmail";
              includeBody = true;
              maxBytes = 20000;
              renewEveryMinutes = 720;
              serve = {
                bind = "127.0.0.1";
                port = 8788;
                path = "/";
              };
              tailscale = {
                mode = "funnel";
                path = "/gmail-pubsub";
              };
            };
          };

          # Local voice transcription using whisper-cpp
          tools.media.audio = {
            enabled = true;
            models = [
              {
                type = "cli";
                command = "${whisperTranscribe}/bin/whisper-transcribe";
                args = ["{{MediaPath}}"];
                timeoutSeconds = 300;
              }
            ];
          };
        };
      };
    };
  };
}
