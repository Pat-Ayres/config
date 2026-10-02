{ pkgs, ... }:
{
  imports = [ ./homebrew.nix ./rectangle.nix ];

  # https://nix-darwin.github.io/nix-darwin/manual/index.html#opt-system.defaults._.GlobalPreferences_._com.apple.mouse.scaling_
  system.defaults = {
    dock.autohide = true;
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleInterfaceStyle = "Dark";
  };

  environment.shells = [ pkgs.zsh ];
  programs.zsh.enable = true;

  fonts.packages = [
    pkgs.nerd-fonts.caskaydia-cove
  ];
}
