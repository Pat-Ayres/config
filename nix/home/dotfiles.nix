{ config, lib, pkgs, ... }:
let
  repo = "${config.home.homeDirectory}/src/config";
  fromRepo = path: config.lib.file.mkOutOfStoreSymlink "${repo}/${path}";
in
{
  home.file = {
    ".bash_aliases".source = fromRepo "bash_aliases";
    ".bashrc".source = fromRepo "bashrc";
    ".gitconfig".source = fromRepo "gitconfig";
    ".inputrc".source = fromRepo "inputrc";
    ".profile".source = fromRepo "profile";
    ".ruby-version".source = fromRepo "ruby-version";
    ".tmux.conf".source = fromRepo "tmux.conf";
    ".zprofile".source = fromRepo "zprofile";
    ".zshaliases".source = fromRepo "zshaliases";
    ".zshrc".source = fromRepo "zshrc";

    ".local/bin/agent-notify".source = fromRepo "bin/agent-notify";
    ".local/bin/cursor-shell-gate".source = fromRepo "bin/cursor-shell-gate";
  };

  xdg.configFile = {
    "starship.toml".source = fromRepo "starship.toml";
    "ghostty/config".source = fromRepo "ghostty/config";
  } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
    "karabiner/karabiner.json".source = fromRepo "macos/karabiner.json";
  };

  xdg.dataFile."chruby".source = "${pkgs.chruby}/share/chruby";

  home.activation.installTpm = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    tpm="$HOME/.tmux/plugins/tpm"
    if [ ! -d "$tpm" ]; then
      run ${pkgs.git}/bin/git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm"
    fi
  '';
}
