{
  inputs,
  lib,
  ...
}: let
  flatsnap = inputs.nixarchy.inputs.nixarchy-flatsnap;
  sourcePrefix = "${flatsnap.outPath}/";
  revision = flatsnap.rev;
  # Nixarchy maps its own option declarations to source URLs, but leaves
  # its flatsnap input as raw store paths. Map those metadata-only paths too,
  # rather than suppressing Nix's missing string-context warning.
  sourceLink = declaration:
    if builtins.isString declaration && lib.hasPrefix sourcePrefix declaration
    then let
      relativePath = lib.removePrefix sourcePrefix declaration;
    in {
      name = relativePath;
      url = "https://github.com/olafkfreund/nixarchy-flatsnap/blob/${revision}/${relativePath}";
    }
    else declaration;
in {
  nixpkgs.overlays = [
    (_final: prev: {
      nixosOptionsDoc = args:
        prev.nixosOptionsDoc (args
          // {
            transformOptions = option: let
              transformed = (args.transformOptions or lib.id) option;
            in
              transformed
              // {
                declarations = map sourceLink transformed.declarations;
              };
          });
    })
  ];
}
