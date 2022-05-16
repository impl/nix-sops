# SPDX-FileCopyrightText: 2021-2022 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{ self, lib, ... }: with lib;
{
  mapActivationPhaseSecrets = f: { activationPhases, secrets, ... }: let
    secretsByActivationPhase = groupBy (secret: secret.value.activationPhase) (mapAttrsToList nameValuePair secrets);
  in mapAttrsToList (activationPhase: secrets: (f {
    activationPhase = activationPhases.${activationPhase};
    secrets = listToAttrs secrets;
  })) secretsByActivationPhase;

  copySourceToStoreSanitized = source: builtins.path {
    path = source.file;
    name = strings.sanitizeDerivationName (builtins.baseNameOf source.file);
  };

  # Copy all source names into a package. This both generates a unique hash of
  # the sources (transitively through their store paths) and prevents the store
  # from garbage collecting inputs.
  mkVersionPkg = { runCommandLocal, ... }: secrets: let
    sourceFiles = unique (builtins.concatMap (secret: (map self.activation.copySourceToStoreSanitized secret.sources)) secrets);
  in runCommandLocal "sops-generation"
    { inherit sourceFiles; }
    ''
      for sourceFile in $sourceFiles; do
        echo $sourceFile >>$out
      done
    '';
}
