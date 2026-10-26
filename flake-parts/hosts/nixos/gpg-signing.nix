{pkgs, ...}: {
  programs.gnupg.agent.pinentryPackage = pkgs.pinentry-qt;

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

    # OpenPGP signing was removed. Do not point git or jj back at the card signer.
    home.activation.migrateGpgSigner = lib.hm.dag.entryAfter ["writeBoundary"] ''
      legacy="${config.home.homeDirectory}/Documents/github-yubikey-setup"
      if [ -d "$legacy/signing" ]; then
        run ${pkgs.gnupg}/bin/gpgconf --homedir "$legacy/signing" --kill all
      fi
      run ${pkgs.jujutsu}/bin/jj config set --user signing.behavior drop
      run ${pkgs.jujutsu}/bin/jj config unset --user signing.key || true
      run ${pkgs.jujutsu}/bin/jj config unset --user signing.backends.gpg.program || true
      if [ -f "$HOME/.gitconfig" ]; then
        run ${pkgs.git}/bin/git config --file "$HOME/.gitconfig" --unset-all user.signingkey || true
        run ${pkgs.git}/bin/git config --file "$HOME/.gitconfig" --unset-all gpg.program || true
        run ${pkgs.git}/bin/git config --file "$HOME/.gitconfig" commit.gpgsign false
        run ${pkgs.git}/bin/git config --file "$HOME/.gitconfig" tag.gpgSign false
      fi
    '';
  };
}
