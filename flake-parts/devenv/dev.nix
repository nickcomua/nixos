# --- flake-parts/devenv/dev.nix
{
  pkgs,
  devenv-root,
  treefmt-wrapper ? null,
  ...
}: {
  # DEVENV:  Fast, Declarative, Reproducible, and Composable Developer
  # Environments using Nix developed by Cachix. For more information refer to
  #
  # - https://devenv.sh/
  # - https://github.com/cachix/devenv

  # --------------------------
  # --- ENV & SHELL & PKGS ---
  # --------------------------
  packages = with pkgs; (
    (lib.optional (treefmt-wrapper != null) treefmt-wrapper)
    ++ [
      # -- NIX UTILS --
      nil # Yet another language server for Nix
      nixd
      statix # Lints and suggestions for the nix programming language
      deadnix # Find and remove unused code in .nix source files
      nix-output-monitor # Processes output of Nix commands to show helpful and pretty information
      nixfmt-rfc-style # An opinionated formatter for Nix
      nixfmt-tree
      # NOTE Choose a different formatter if you'd like to
      # nixfmt # An opinionated formatter for Nix
      # alejandra # The Uncompromising Nix Code Formatter

      # -- GIT RELATED UTILS --
      # commitizen # Tool to create committing rules for projects, auto bump versions, and generate changelogs
      # cz-cli # The commitizen command line utility
      # fh # The official FlakeHub CLI
      # gh # GitHub CLI tool
      # gh-dash # Github Cli extension to display a dashboard with pull requests and issues

      # -- BASE LANG UTILS --
      markdownlint-cli # Command line interface for MarkdownLint
      # nodePackages.prettier # Prettier is an opinionated code formatter
      # typos # Source code spell checker

      # -- (YOUR) EXTRA PKGS --
    ]
  );

  enterShell = ''
    # Welcome splash text
    echo ""; echo -e "\e[1;37;42mWelcome to the nixos devshell!\e[0m"; echo ""
  '';

  # ---------------
  # --- SCRIPTS ---
  # ---------------
  scripts = {
    "rename-project".exec = ''
      find $1 \( -type d -name .git -prune \) -o -type f -print0 | xargs -0 sed -i "s/nixos/$2/g"
    '';
  };

  # -----------------
  # --- LANGUAGES ---
  # -----------------
  languages.nix.enable = true;

  # ----------------------------
  # --- PROCESSES & SERVICES ---
  # ----------------------------

  # ------------------
  # --- CONTAINERS ---
  # ------------------
  # Disable containers to allow flake check to pass
  containers = pkgs.lib.mkForce {};

  # ----------------------
  # --- BINARY CACHING ---
  # ----------------------
  # cachix.pull = [ "pre-commit-hooks" ];
  # cachix.push = "NAME";

  # ------------------------
  # --- GIT HOOKS ---
  # ------------------------
  # NOTE All available hooks options are listed at
  # https://devenv.sh/reference/options/#git-hooks
  git-hooks = {
    hooks = {
      treefmt.enable =
        if (treefmt-wrapper != null)
        then true
        else false;
      treefmt.package =
        if (treefmt-wrapper != null)
        then treefmt-wrapper
        else pkgs.treefmt;

      nil.enable = true; # Nix Language server, an incremental analysis assistant for writing in Nix.
      markdownlint.enable = true; # Markdown lint tool
      # typos.enable = true; # Source code spell checker

      # actionlint.enable = true; # GitHub workflows linting
      # commitizen.enable = true; # Commitizen is release management tool designed for teams.
      editorconfig-checker.enable = true; # A tool to verify that your files are in harmony with your .editorconfig
    };
  };

  # --------------
  # --- FLAKES ---
  # --------------
  devenv.flakesIntegration = true;

  # This is currently needed for devenv to properly run in pure hermetic
  # mode while still being able to run processes & services and modify
  # (some parts) of the active shell.
  devenv.root = let
    devenvRootFileContent = builtins.readFile devenv-root.outPath;
    hasValidRoot =
      devenvRootFileContent
      != ""
      && devenvRootFileContent != "/dev/null\n"
      && devenvRootFileContent != "/dev/null";
  in
    # Use /tmp as fallback for flake check (needs absolute path)
    if hasValidRoot
    then devenvRootFileContent
    else "/tmp/devenv-flake-check";

  # ---------------------
  # --- MISCELLANEOUS ---
  # ---------------------
  difftastic.enable = true;

  cachix = {
    pull = ["nickcomua"];
    push = "nickcomua";
  };
}
