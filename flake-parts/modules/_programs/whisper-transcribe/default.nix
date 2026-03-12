# Whisper transcription tool for OpenClaw
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.whisper-transcribe;
  whisperTranscribe = import ./package.nix {inherit pkgs lib;};
  whisperDictate = import ./dictate.nix {inherit pkgs lib;};
in {
  options.programs.whisper-transcribe = {
    enable = mkEnableOption "Whisper transcription tool";

    package = mkOption {
      type = types.package;
      default = whisperTranscribe;
      description = "Whisper transcribe package";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      whisperDictate.startScript
      whisperDictate.stopScript
    ];
  };
}
