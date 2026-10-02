{
  description = "Pat Ayres cross-platform system config: nix-darwin + home-manager on macOS, standalone home-manager on Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative bridge to Homebrew, used only where brew is notably
    # better than nixpkgs on Darwin (mainly GUI casks).
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, darwin, home-manager, nix-homebrew, neovim-nightly-overlay, ... }:
    let
      overlays = [ neovim-nightly-overlay.overlays.default ];
    in
    {
      # first run: `nix run nix-darwin -- switch --flake ~/src/config#patrick-ayres-mb`
      # `sudo darwin-rebuild switch --flake ~/src/config#patrick-ayres-mb`
      darwinConfigurations."patrick-ayres-mb" = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          { nixpkgs.overlays = overlays; }
          ./nix/hosts/patrick-ayres-mb
          ./nix/darwin
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.payres = import ./nix/home;
            home-manager.backupFileExtension = "bak";
          }
        ];
      };

      # home-manager switch --flake ~/src/config#payres@linux
      homeConfigurations."payres@linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { system = "x86_64-linux"; inherit overlays; };
        modules = [ ./nix/home ];
      };
    };
}
