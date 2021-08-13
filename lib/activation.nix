# SPDX-FileCopyrightText: 2021 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{ lib, ... }: with lib;
{
  mapActivationPhaseSecrets = f: { activationPhases, secrets, ... }: let
    secretsByActivationPhase = groupBy (secret: secret.value.activationPhase) (mapAttrsToList nameValuePair secrets);
  in mapAttrsToList (activationPhase: secrets: (f {
    activationPhase = activationPhases.${activationPhase};
    secrets = listToAttrs secrets;
  })) secretsByActivationPhase;

  # Build a set of symlink entries that will be unique over all SOPS sources
  # for the current configuration. Any time the sources change, the store name
  # corresponding to a link farm of these entries will also change.
  mkVersionLinkFarmEntries = secrets: let
    mkSourceLink = prefix: i: { file, ... }: {
      name = "${prefix}source-${builtins.toString i}";
      path = file;
    };
    mkSecretLink = i: { sources, ... }: imap1 (mkSourceLink "secret-${builtins.toString i}-") sources;
    secretLinks = imap1 mkSecretLink secrets;
  in builtins.concatLists secretLinks;
}
