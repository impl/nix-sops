# SPDX-FileCopyrightText: 2021-2022 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

let
  flake = builtins.getFlake (toString ../.);
in
  { self ? flake.outputs
  , inputs ? flake.inputs
  , system ? builtins.currentSystem
  }:
  let
    pkgs = import inputs.nixpkgs { inherit system; };

    mkNixosTest = file: pkgs.nixosTest (args: import file (args // {
      inherit self inputs system;
    }));
  in builtins.mapAttrs (name: file: mkNixosTest file) {
    nixosActivation = ./nixos/activation.nix;
    nixosBootSecrets = ./nixos/boot-secrets.nix;
    nixosInstall = ./nixos/install.nix;
    nixosSimple = ./nixos/simple.nix;

    homeManagerSimple = ./home-manager/simple.nix;
  }
