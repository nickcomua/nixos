{
  pkgs,
  config,
  ...
}: {
  system.fsPackages = [pkgs.apfsprogs];
  boot.extraModulePackages = [
    (config.boot.kernelPackages.apfs.overrideAttrs (old: {
      # Upstream compatibility fix; nixpkgs still packages the older driver.
      patches =
        (old.patches or [])
        ++ [
          (pkgs.fetchurl {
            url = "https://github.com/linux-apfs/linux-apfs-rw/commit/59c45efa336750c5134aa962c8b4f8b0b56f92ad.patch";
            hash = "sha256-wjROQ8ngxtGSDwuOeSTU2CrwXuBke3Xotmc2cQGcxQY=";
          })
        ];
    }))
  ];
  boot.initrd.kernelModules = ["apfs"];
}
