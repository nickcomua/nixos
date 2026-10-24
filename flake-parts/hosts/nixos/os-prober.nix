{
  # Keep automatic Windows detection, but do not probe nonexistent mapper
  # paths emitted when dmraid reports that no RAID devices were found.
  nixpkgs.overlays = [
    (_final: prev: {
      os-prober = prev.os-prober.overrideAttrs (old: {
        patches = (old.patches or []) ++ [./os-prober-missing-devices.patch];
      });
    })
  ];
}
