args@{ lib, ... }: with lib;
let
  mkLib = self:
    let
      importLib = file: import file ({ inherit self; } // args);
    in
    {
      activation = importLib ./activation.nix;
      options = importLib ./options.nix;

      inherit (self.activation) mapActivationPhaseSecrets;
      inherit (self.options) activationPhasesOption mkSecretsOption;
    };
in makeExtensible mkLib
