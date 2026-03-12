# Push-to-talk dictation script for Wayland
# Hold key to record, release to transcribe, paste to clipboard + active field
{
  pkgs,
  lib,
}: let
  whisperTranscribe = import ./package.nix {inherit pkgs lib;};
  recordingFile = "/tmp/whisper-dictate.wav";
  recorderPidFile = "/tmp/whisper-dictate-recorder.pid";

  startScript = pkgs.writeShellScriptBin "whisper-dictate-start" ''
    # Kill any previous recording
    if [ -f "${recorderPidFile}" ]; then
      kill "$(cat "${recorderPidFile}")" 2>/dev/null || true
      rm -f "${recorderPidFile}" "${recordingFile}"
    fi

    # Start recording with PipeWire
    ${pkgs.pipewire}/bin/pw-record \
      --rate 16000 \
      --channels 1 \
      --format s16 \
      "${recordingFile}" &
    echo $! > "${recorderPidFile}"

    ${pkgs.libnotify}/bin/notify-send -t 10000 -h string:x-canonical-private-synchronous:whisper-dictate "Dictation" "Recording..."
  '';

  stopScript = pkgs.writeShellScriptBin "whisper-dictate-stop" ''
    # Stop recording
    if [ -f "${recorderPidFile}" ]; then
      kill "$(cat "${recorderPidFile}")" 2>/dev/null || true
      rm -f "${recorderPidFile}"
      sleep 0.3
    else
      exit 0
    fi

    # Check if we got any audio
    if [ ! -f "${recordingFile}" ] || [ ! -s "${recordingFile}" ]; then
      ${pkgs.libnotify}/bin/notify-send -t 2000 -h string:x-canonical-private-synchronous:whisper-dictate "Dictation" "No audio recorded"
      exit 0
    fi

    ${pkgs.libnotify}/bin/notify-send -t 30000 -h string:x-canonical-private-synchronous:whisper-dictate "Dictation" "Transcribing..."

    # Transcribe with GPU-accelerated whisper
    TEXT=$(${whisperTranscribe}/bin/whisper-transcribe "${recordingFile}" 2>/dev/null || echo "")
    rm -f "${recordingFile}"

    if [ -z "$TEXT" ]; then
      ${pkgs.libnotify}/bin/notify-send -t 2000 -h string:x-canonical-private-synchronous:whisper-dictate "Dictation" "No speech detected"
      exit 0
    fi

    # Copy to clipboard
    echo -n "$TEXT" | ${pkgs.wl-clipboard}/bin/wl-copy

    # Type into active field
    ${pkgs.wtype}/bin/wtype -- "$TEXT"

    ${pkgs.libnotify}/bin/notify-send -t 3000 -h string:x-canonical-private-synchronous:whisper-dictate "Dictation" "$TEXT"
  '';
in {
  inherit startScript stopScript;
}
