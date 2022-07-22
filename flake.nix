# SPDX-FileCopyrightText: 2021 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{
  inputs = {
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
  let
    lib = import ./lib {
      inherit inputs;
      inherit (nixpkgs) lib;
    };

    mkMod = mod: {
      imports = [ mod ];

      _module.args = { inherit self inputs; };
    };
  in
  {
    inherit lib;

    checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: import ./tests/all-tests.nix {
      inherit system self inputs;
    });

    nixosModules = rec {
      sops = mkMod ./modules/nixos;
      default = sops;
    };

    homeModules = rec {
      sops = mkMod ./modules/home-manager.nix;
      default = sops;
    };
  };
}
