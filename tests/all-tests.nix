let
  flake = builtins.getFlake (toString ../.);
in
  { self ? flake.outputs
  , inputs ? flake.inputs
  , system ? builtins.currentSystem
  }:
  let
    pkgs = import inputs.nixpkgs { inherit system; };

    mkNixosTest = file: pkgs.nixosTest (args: import file {
      inherit self inputs pkgs system;
    } // args);
  in pkgs.lib.mapAttrs (name: file: mkNixosTest file) {
    nixosBootSecrets = ./nixos/boot-secrets.nix;
    nixosInstall = ./nixos/install.nix;
    nixosSimple = ./nixos/simple.nix;

    homeManagerSimple = ./home-manager/simple.nix;
  }
