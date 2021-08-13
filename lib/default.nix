# SPDX-FileCopyrightText: 2021 Noah Fontes
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

      inherit (self.activation)
        mapActivationPhaseSecrets
        mkVersionLinkFarmEntries;
      inherit (self.options)
        activationPhasesOption
        mkSecretsOption;
    };
in makeExtensible mkLib
