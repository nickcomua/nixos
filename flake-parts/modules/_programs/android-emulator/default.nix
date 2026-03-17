# Android emulator with KVM acceleration and development tools
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.android-emulator;
in {
  options.programs.android-emulator = {
    enable = mkEnableOption "Android emulator and SDK tools";

    enableKVM = mkOption {
      type = types.bool;
      default = true;
      description = "Enable KVM hardware acceleration";
    };

    enableADB = mkOption {
      type = types.bool;
      default = true;
      description = "Enable ADB (Android Debug Bridge)";
    };
  };

  config = mkIf cfg.enable {
    # Enable KVM for hardware acceleration
    boot.kernelModules = mkIf cfg.enableKVM ["kvm-amd"];

    # Android development environment
    environment.systemPackages = with pkgs; [
      # Android SDK and emulator
      androidenv.androidPkgs_9_0.platform-tools # ADB, fastboot, etc
      androidenv.androidPkgs_9_0.emulator # Android emulator

      # Additional tools for rooting and development
      scrcpy # Android screen mirroring and control
      gnirehtet # Reverse tethering over adb

      # Development tools
      openjdk17 # Java for Android development
      gradle # Build tool

      # File transfer and networking
      wget
      curl
      unzip

      # For custom ROM/kernel building if needed
      git
      python3

      # ADB shell and debugging tools
      android-tools # Alternative ADB implementation
    ];

    # Configure Android SDK environment variables
    environment.variables = {
      ANDROID_HOME = "${pkgs.androidenv.androidPkgs_9_0.androidsdk}/libexec/android-sdk";
      ANDROID_SDK_ROOT = "${pkgs.androidenv.androidPkgs_9_0.androidsdk}/libexec/android-sdk";
    };

    # Add Android SDK to PATH
    environment.extraInit = ''
      export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools
    '';

    # Configure users and groups for Android development
    users = {
      groups.android = {};
      groups.adbusers = {};
      users.nick = {
        extraGroups = ["android" "kvm" "adbusers"];
      };
    };

    # udev rules for Android devices
    services.udev.packages = [pkgs.android-udev-rules];

    # Enable ADB over network (for emulator access)
    services.udev.extraRules = mkIf cfg.enableADB ''
      # Android emulator and device access
      SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="android"
      SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", GROUP="android"
      SUBSYSTEM=="usb", ATTR{idVendor}=="22b8", MODE="0666", GROUP="android"

      # KVM access for emulator acceleration
      KERNEL=="kvm", GROUP="kvm", MODE="0666"
    '';

    # Networking for emulator
    networking.firewall.allowedTCPPorts = [
      5037 # ADB daemon
      5554 # Emulator console
      5555 # Emulator ADB
    ];
  };
}
