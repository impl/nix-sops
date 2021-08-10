{ lib, ... }: with lib;
{
  mapActivationPhaseSecrets = f: { activationPhases, secrets, ... }: let
    secretsByActivationPhase = groupBy (secret: secret.value.activationPhase) (mapAttrsToList nameValuePair secrets);
  in mapAttrsToList (activationPhase: secrets: (f {
    activationPhase = activationPhases.${activationPhase};
    secrets = listToAttrs secrets;
  })) secretsByActivationPhase;
}
