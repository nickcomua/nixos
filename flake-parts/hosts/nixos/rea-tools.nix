# Native REA providers: reproducible, isolated from Hermes's Python runtime.
{ pkgs, ... }:
let
  unicorn212 = pkgs.unicorn.overrideAttrs (_: {
    version = "2.1.2";
    src = pkgs.fetchFromGitHub {
      owner = "unicorn-engine";
      repo = "unicorn";
      tag = "2.1.2";
      hash = "sha256-qA84xBztyWmt/rUExhhZMkQzvDPx0UE9MAIPG/Su3iE=";
    };
  });
  analysisPython = pkgs.python313.override {
    packageOverrides = final: prev: {
      pyelftools = prev.pyelftools.overridePythonAttrs (_: {
        version = "0.33";
        src = pkgs.fetchFromGitHub {
          owner = "eliben";
          repo = "pyelftools";
          tag = "v0.33";
          hash = "sha256-NqF5A6PRl4uncwNS9j44fIV7ovlljiucvV2Msv0LK/w=";
        };
      });
      unicorn = (prev.unicorn.override { unicorn = unicorn212; }).overridePythonAttrs (old: {
        build-system = (old.build-system or [ ]) ++ [ final.versioningit ];
        postPatch = (old.postPatch or "") + ''
          substituteInPlace pyproject.toml --replace-fail \
            '[tool.versioningit]' '[tool.versioningit]
          default-version = "2.1.2"'
        '';
      });
    };
  };
  elfPython = analysisPython.withPackages (p: [ p.pwntools p.pyelftools p.unicorn ]);
  reaPython = pkgs.writeShellScriptBin "rea-elf-python" ''
    exec ${elfPython}/bin/python3 "$@"
  '';
in
{
  assertions = [
    {
      assertion = analysisPython.pkgs.pwntools.version == "4.15.0";
      message = "REA's verified offline ELF provider requires pwntools 4.15.0.";
    }
  ];
  environment.systemPackages = [ pkgs.ghidra pkgs.jdk21 reaPython ];
  # Stable paths for MCP registrations; rebuilt store paths stay GC-rooted.
  environment.etc."rea/ghidra".source = "${pkgs.ghidra}/lib/ghidra";
  environment.etc."rea/jdk".source = pkgs.jdk21.home;
  environment.etc."rea/python".source = elfPython;
}
