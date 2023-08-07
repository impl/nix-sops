# SPDX-FileCopyrightText: 2021-2022 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{ self, config, lib, pkgs, ... }: with lib;
let
  cfg = config.sops;

  initrdSecretPath = "/sops/age.txt";
  ageKeyFile = "/run/keys/sops/age.txt";

  secretsScript = ''
    test -n "$(${pkgs.age}/bin/age-keygen -y ${cfg.bootSecrets.${initrdSecretPath}.target})" \
      && cp -a ${cfg.bootSecrets.${initrdSecretPath}.target} ${ageKeyFile}
  '';
in
{
  options = {
    sops = {
      ageKeySecretSource = mkOption {
        type = types.nullOr self.lib.options.secretSourceType;
        default = null;
        description = ''
          A global key that is already encrypted to use as the main SOPS
          decryption key for this module. This key must be decryptable by
          other means to facilitate bootstrapping the module.

          To prevent referential errors, its content will be copied from the
          desired secret instead of linked.
        '';
      };
    };
  };

  config = mkIf (cfg.ageKeySecretSource != null) {
    sops.bootSecrets.${initrdSecretPath} = mkForce {
      sources = [ (cfg.ageKeySecretSource // { outputType = "binary"; }) ];
      availableInBootedSystem = true;
    };

    boot.initrd.postMountCommands = mkAfter secretsScript;
    system.activationScripts = mkMerge [
      {
        "sopsAgeKey" = stringAfter [ "sopsBootSecrets" ] secretsScript;
      }
      (mkMerge (self.lib.mapActivationPhaseSecrets ({ activationPhase, ... }: {
        ${activationPhase.activationScriptsKey}.deps = [ "sopsAgeKey" ];
      }) cfg))
    ];

    sops.ageKeyFile = ageKeyFile;

    systemd.tmpfiles.rules = [
      "z ${ageKeyFile} 0600 root ${builtins.toString config.ids.gids.keys} - -"
    ];
  };
}
