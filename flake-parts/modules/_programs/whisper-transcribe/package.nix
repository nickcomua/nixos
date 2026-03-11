# Whisper transcription package
# Shared between NixOS module and home-manager module
{
  pkgs,
  lib,
}: let
  # Use Vulkan-accelerated whisper-cpp on Linux, regular on macOS
  whisperPackage =
    if pkgs.stdenv.isLinux
    then pkgs.whisper-cpp-vulkan
    else pkgs.whisper-cpp;

  inherit (pkgs.stdenv) isLinux;
in
  pkgs.writeShellScriptBin "whisper-transcribe" ''
    set -euo pipefail

    if [ $# -lt 1 ]; then
      echo "Usage: whisper-transcribe <audio_file>" >&2
      exit 1
    fi

    AUDIO_FILE="$1"
    MODEL_SIZE="''${WHISPER_MODEL:-large-v3}"
    CACHE_DIR="''${HOME}/.cache/whisper"
    MODEL_FILE="$CACHE_DIR/ggml-$MODEL_SIZE.bin"

    # Download model if not present
    if [ ! -f "$MODEL_FILE" ]; then
      mkdir -p "$CACHE_DIR"
      echo "Downloading whisper $MODEL_SIZE model..." >&2
      ${pkgs.curl}/bin/curl -L -o "$MODEL_FILE" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL_SIZE.bin"
    fi

    ${lib.optionalString isLinux ''
      # Vulkan ICD setup for AMD GPU on Linux
      export VK_ICD_FILENAMES="${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
      export LD_LIBRARY_PATH="${pkgs.vulkan-loader}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      # Tell ggml where to find the Vulkan backend library
      export GGML_BACKEND_DIR="${whisperPackage}/lib"
    ''}

    # Convert non-WAV audio to WAV (whisper-cpp only reads WAV)
    CONVERTED=""
    case "$AUDIO_FILE" in
      *.wav|*.WAV) ;;
      *)
        CONVERTED="$(mktemp /tmp/whisper-XXXXXX.wav)"
        ${pkgs.ffmpeg}/bin/ffmpeg -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$CONVERTED" -y 2>/dev/null
        AUDIO_FILE="$CONVERTED"
        ;;
    esac

    cleanup() { [ -n "$CONVERTED" ] && rm -f "$CONVERTED"; }
    trap cleanup EXIT

    # Run whisper-cpp and extract just the text (remove timestamps)
    ${whisperPackage}/bin/whisper-cli \
      -m "$MODEL_FILE" \
      -f "$AUDIO_FILE" \
      --no-timestamps \
      -otxt \
      2>/dev/null | grep -v "^\[" | tr -d '\n'
  ''
