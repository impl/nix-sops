# SPDX-FileCopyrightText: 2021-2022 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{ self, config, inputs, lib, pkgs, ... }: with lib;
let
  cfg = config.sops;

  versionPkg = self.lib.mkVersionPkg pkgs (attrValues cfg.secrets);
  generationPath = "${builtins.toString (/. + cfg.storagePath)}/${builtins.baseNameOf versionPkg}";

  getSecretPath = name: generationPath + "/secrets-${strings.sanitizeDerivationName name}-${builtins.hashString "sha256" name}";

  initScript = ''
    mkdir -p ${escapeShellArg generationPath}
    chmod 0700 ${escapeShellArg cfg.storagePath}
    chmod 0700 ${escapeShellArg generationPath}
  '';

  # Create a package that contains all store symbolic links.
  linkPkg = pkgs.linkFarm "sops-secret-links" (mapAttrsToList (name: secret: {
    inherit name;
    path = getSecretPath name;
  }) cfg.secrets);

  # Option type (dependent on linkPkg to resolve the target).
  secretsOption = self.lib.mkSecretsOption {
    extraModules = toList ({ name, ... }: {
      config = {
        target = linkPkg + "/${name}";
        activationPhase = mkDefault "whenever";
      };
    });
  };

  mkSecretScript = { name, secret }: let
    secretPath = getSecretPath name;
    targetI = escapeShellArg (secretPath + ".i");
    target = escapeShellArg secretPath;
  in self.lib.mkShellAndIfList (flatten [
    "$DRY_RUN_CMD truncate -s 0 ${targetI}"
    (map (source: "$DRY_RUN_CMD ${pkgs.sops}/bin/sops --config /dev/null --decrypt ${optionalString (source.outputType != null) "--output-type ${escapeShellArg source.outputType}"} ${optionalString (source.key != null) "--extract ${escapeShellArg source.key}"} ${escapeShellArg (self.lib.copySourceToStoreSanitized source)} >>${targetI}") secret.sources)
    "$DRY_RUN_CMD chmod ${escapeShellArg secret.mode} ${targetI}"
    "$DRY_RUN_CMD mv -Tf ${targetI} ${target}"
  ]);

  mkSecretsScript = secrets: ''
    ${optionalString (config.sops.ageKeyFile != null) ''
      $DRY_RUN_CMD export SOPS_AGE_KEY_FILE=${escapeShellArg config.sops.ageKeyFile}
    ''}
    $DRY_RUN_CMD export SOPS_GPG_EXEC=${pkgs.gnupg}/bin/gpg

    ${concatStringsSep "\n" (mapAttrsToList (name: secret: mkSecretScript { inherit name secret; }) secrets)}
  '';
in
{
  options = {
    sops = {
      activationPhases = self.lib.activationPhasesOption;

      secrets = secretsOption;

      storagePath = mkOption {
        type = types.path;
        description = ''
          The runtime location to store secret data. This directory will be
          created if it doesn't exist.
        '';
        default = config.xdg.dataHome + "/sops";
        example = literalExample ''
          /tmp + "/sops-per-user-${config.home.username}"
        '';
      };

      ageKeyFile = mkOption {
        type = types.nullOr types.path;
        description = ''
          The location of the age private key(s) to load.
        '';
        default = null;
        example = literalExample ''
          /. + config.home.homeDirectory + "/keys.txt";
        '';
      };
    };
  };

  config = mkIf (cfg.secrets != {}) {
    assertions = mapAttrsToList (name: secret: {
      assertion = hasAttr secret.activationPhase cfg.activationPhases;
      message = "The activation phase ${strings.escapeNixIdentifier secret.activationPhase} used by sops.secrets.${strings.escapeNixIdentifier name} is not defined.";
    }) cfg.secrets;

    sops.activationPhases = {
      "whenever" = { };
    };

    home.activation = let
      inherit (inputs.home-manager.lib.hm) dag;
    in mkMerge [
      {
        sopsInit = dag.entryAfter [ "writeBoundary" ] initScript;
      }
      (mkMerge (self.lib.mapActivationPhaseSecrets ({ activationPhase, secrets }: {
        ${activationPhase.activationScriptsKey} = dag.entryBetween activationPhase.before ([ "sopsInit" ] ++ activationPhase.after) (mkSecretsScript secrets);
      }) cfg))
    ];

    systemd.user.tmpfiles.rules = [
      "e ${escapeShellArg cfg.storagePath} 0700 - - 0 -"
      "z ${escapeShellArg generationPath} 0700 - - - -"
    ];
  };
}
