_: {
  flake.nixosModules = {
    # NOTE Dogfooding your modules with `importApply` will make them more
    # reusable even outside of your flake. For more info see
    # https://flake.parts/dogfood-a-reusable-module#example-with-importapply

    # Programs are imported directly in host configs to avoid evaluation
    # issues during flake check (modules reference NixOS-specific options)
    # horse-browser = ./programs/horse-browser;
    # librepods = ./programs/librepods;

    # Monitoring: Grafana + Prometheus (node_exporter + comin) + Loki + Promtail
    monitoring = ./monitoring.nix;
  };
}
