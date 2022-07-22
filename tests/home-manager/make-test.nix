# SPDX-FileCopyrightText: 2021-2022 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

f: args@{ self, inputs, pkgs, ... }: let
  mkTest = { name, module, testScript }: {
    inherit name;

    nodes.machine = { config, ... }: {
      users.users."hm-user" = {
        isNormalUser = true;
        packages = [
          (inputs.home-manager.lib.homeManagerConfiguration {
            pkgs = inputs.nixpkgs.legacyPackages.${config.nixpkgs.system};
            modules = [
              self.homeModules.default
              module
              {
                xdg.enable = true;
                manual.manpages.enable = false;
                home = {
                  username = "hm-user";
                  homeDirectory = config.users.users."hm-user".home;
                  stateVersion = "22.11";
                };
              }
            ];
          }).activationPackage
        ];
      };

      nix.settings.allowed-users = [ "hm-user" ];
    };

    testScript = ''
      machine.wait_for_unit('multi-user.target');
      machine.succeed('su - hm-user -c home-manager-generation');

      ${testScript}
    '';
  };
in mkTest (if pkgs.lib.isFunction f then f args else f)
