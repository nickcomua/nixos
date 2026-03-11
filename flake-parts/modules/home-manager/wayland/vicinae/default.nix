{pkgs, ...}: {
  services.vicinae = {
    enable = true;
    systemd.enable = true; # enables systemd service
    # systemd.autoStart = true; # default: true
    #package = pkgs.vicinae; # Use package from nixpkgs instead of flake
  };

  # create a configfile from ./vicinae.json
  xdg.configFile."vicinae/config.json".source = ./vicinae.json;
}
