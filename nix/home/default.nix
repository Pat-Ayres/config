{ pkgs, ... }:
{
  imports = [
    ./packages.nix
    ./dotfiles.nix
    ./hooks.nix
  ];

  home.username = "payres";
  home.homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/payres" else "/home/payres";

  # Tracks the home-manager release you first activated with. Don't bump
  # without reading the release notes for the version you're jumping to.
  # https://nix-community.github.io/home-manager/release-notes/rl-2605.html
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = false;
    enableBashIntegration = false;
  };
}
