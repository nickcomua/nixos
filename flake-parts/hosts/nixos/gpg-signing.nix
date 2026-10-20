{pkgs, ...}: let
  signer = pkgs.writeShellApplication {
    name = "git-gpg";
    runtimeInputs = [pkgs.gnupg];
    text = builtins.readFile ./gpg-sign.sh;
  };
in {
  programs.gnupg.agent.pinentryPackage = pkgs.pinentry-qt;
  environment.systemPackages = [signer];

  home-manager.users.nick = {
    config,
    lib,
    pkgs,
    ...
  }: {
    programs.gpg = {
      enable = true;
      # pcscd already manages this host's smartcard reader. Do not compete for
      # its USB interface through scdaemon's built-in, exclusive CCID driver.
      scdaemonSettings.disable-ccid = true;
    };
    programs.git.signing.signer = lib.mkForce (lib.getExe signer);

    # gg updates recent-workspaces in this file, so retain a writable jj config
    # and change only the signer rather than replacing it with a store symlink.
    home.activation.migrateGpgSigner = lib.hm.dag.entryAfter ["writeBoundary"] ''
      legacy="${config.home.homeDirectory}/Documents/github-yubikey-setup"
      if [ -d "$legacy/signing" ]; then
        run ${pkgs.gnupg}/bin/gpgconf --homedir "$legacy/signing" --kill all
      fi
      run ${pkgs.jujutsu}/bin/jj config set --user signing.backends.gpg.program ${lib.getExe signer}
      if [ -f "$HOME/.gitconfig" ] && \
         [ "$(${pkgs.git}/bin/git config --file "$HOME/.gitconfig" --get gpg.program || true)" = "$legacy/git-gpg" ]; then
        run ${pkgs.git}/bin/git config --file "$HOME/.gitconfig" gpg.program ${lib.getExe signer}
      fi
    '';
  };
}
