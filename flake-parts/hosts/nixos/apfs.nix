{
  lib,
  pkgs,
  config,
  ...
}: {
  # APFS 0.3.21 still uses the inode create API removed in Linux 7.3.
  # Keep receiving 7.2 patch releases until the driver supports the new API.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_7_2;
  system.fsPackages = [pkgs.apfsprogs];
  boot.extraModulePackages = [config.boot.kernelPackages.apfs];
  boot.initrd.kernelModules = ["apfs"];
}
