# SPDX-FileCopyrightText: 2021-2022 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

args@{ lib, ... }: with lib;
let
  mkLib = self:
    let
      importLib = file: import file ({ inherit self; } // args);
    in
    {
      activation = importLib ./activation.nix;
      options = importLib ./options.nix;
      shell = importLib ./shell.nix;

      inherit (self.activation)
        mapActivationPhaseSecrets
        copySourceToStoreSanitized
        mkVersionPkg;
      inherit (self.options)
        activationPhasesOption
        mkSecretsOption;
      inherit (self.shell)
        mkShellAndIfList;
    };
in makeExtensible mkLib
