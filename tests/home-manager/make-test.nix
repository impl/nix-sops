{ name, configuration, testScript }:
{ self, inputs, ... }:
{
  inherit name;

  machine = { config, ... }: {
    users.users."hm-user" = {
      isNormalUser = true;
      packages = [
        (inputs.home-manager.lib.homeManagerConfiguration {
          inherit configuration;
          inherit (config.nixpkgs) system;
          username = "hm-user";
          homeDirectory = config.users.users."hm-user".home;

          extraModules = [
            self.homeModule
            {
              xdg.enable = true;
              manual.manpages.enable = false;
            }
          ];
        }).activationPackage
      ];
    };

    nix.allowedUsers = [ "hm-user" ];
  };

  testScript = ''
    machine.wait_for_unit('multi-user.target');
    machine.succeed('su - hm-user -c home-manager-generation');

    ${testScript}
  '';
}
