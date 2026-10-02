{ ... }:
{
  nix-homebrew = {
    enable = true;
    user = "payres";
    autoMigrate = true;
  };

  # Nix is primary. Homebrew is only for things nixpkgs doesn't do well on
  # Darwin — almost always GUI casks.
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # "zap" removes anything installed via brew that isn't declared below.
      cleanup = "zap";
    };

    taps = [];

    casks = [
      "rectangle"
      "karabiner-elements"
      "ghostty"
      "1password"
      "firefox"
      "claude"
      "joplin"
    ];

    brews = [
      "ruby-install"
    ];
  };
}
