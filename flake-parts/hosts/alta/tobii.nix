# Alta (Libre AML-A311D-CC) as the Tobii 4C test host.
# Copied from the tobi repo (tools/alta/alta-tobi.nix @ ef925b7e) so this flake
# stays pure. The DT overlay only takes effect after a reboot.
{pkgs, ...}: {
  # Free 5V_EN = GPIOH_8 (gpiochip0 line 24) from the always-on regulator-vcc-5v so
  # userspace can cut VBUS of all 4 USB-A ports (tobi tools/alta/power-cycle.sh).
  # An empty "gpio" property makes reg-fixed-voltage find no enable GPIO (-ENOENT ->
  # optional -> none); VCC_5V stays a plain always-on regulator in software, and the
  # pin stays an input at boot, so the board's pull-up keeps VCC5V ON by default.
  # (Overlays cannot delete properties; overriding with an empty value is the idiom.)
  hardware.deviceTree.overlays = [
    {
      name = "alta-free-5v-en";
      dtsText = ''
        /dts-v1/;
        /plugin/;
        / {
          compatible = "libretech,aml-a311d-cc";
          fragment@0 {
            target-path = "/regulator-vcc-5v";
            __overlay__ { gpio; };
          };
        };
      '';
    }
  ];

  # Tobii 4C runtime (0127) and update/FBL (0102): rw for wheel + active seat.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="2104", ATTR{idProduct}=="0127", MODE="0660", GROUP="wheel", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="2104", ATTR{idProduct}=="0102", MODE="0660", GROUP="wheel", TAG+="uaccess"
    # GPIOH_8 (VBUS) for wheel without root
    SUBSYSTEM=="gpio", KERNEL=="gpiochip0", MODE="0660", GROUP="wheel"
  '';

  environment.systemPackages = with pkgs; [libgpiod usbutils uhubctl rsync];
}
