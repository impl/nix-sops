{
  inputs = {
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };

    nmt = {
      url = "gitlab:rycee/nmt";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
  let
    lib = nixpkgs.lib.extend (final: prev: {
      my = import ./lib {
        inherit inputs;
        lib = final;
      };
    });

    mkMod = mod: {
      imports = [ mod ];

      _module.args = { inherit self inputs; };
    };
  in
  {
    lib = lib.my;

    checks = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: import ./tests/all-tests.nix {
      inherit system self inputs;
    });

    nixosModules = {
      sops = mkMod ./modules/nixos;
    };
    nixosModule = self.nixosModules.sops;

    homeModules = {
      sops = mkMod ./modules/home-manager.nix;
    };
    homeModule = self.homeModules.sops;
  };
}
