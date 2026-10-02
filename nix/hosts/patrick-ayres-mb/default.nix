{ ... }:
{
  networking.hostName = "patrick-ayres-mb";
  networking.computerName = "patrick-ayres-mb";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.primaryUser = "payres";
  users.users.payres.home = "/Users/payres";

  # Tracks the nix-darwin release you first activated with
  # https://github.com/nix-darwin/nix-darwin/blob/master/CHANGELOG
  system.stateVersion = 7;
}
