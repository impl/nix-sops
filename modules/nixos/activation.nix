# SPDX-FileCopyrightText: 2021 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{ self, config, generationPath, lib, pkgs, ... }: with lib;
let
  inherit (config) users;

  cfg = config.sops;

  # Stable path for a secret outside of the store.
  getSecretPath = name: generationPath + "/secrets-${strings.sanitizeDerivationName name}-${builtins.hashString "sha256" name}";

  # Create a package that contains all store symbolic links.
  linkPkg = pkgs.linkFarm "sops-secret-links" (mapAttrsToList (name: secret: {
    inherit name;
    path = getSecretPath name;
  }) cfg.secrets);

  # Option type (dependent on linkPkg to resolve the target).
  secretsOption = self.lib.mkSecretsOption {
    extraModules = toList ({ name, config, ... }: {
      options = {
        owner = mkOption {
          type = types.str;
          default = "root";
          description = "The owner of the created file.";
        };
        group = mkOption {
          type = types.str;
          description = "The group to assign to the created file.";
        };
      };

      config = {
        target = linkPkg + "/${name}";
        group = mkDefault users.users.${config.owner}.group;
        activationPhase = mkDefault (if config.owner == "root" && config.group == users.users."root".group then "forRoot" else "forUser");
      };
    });
  };

  mkSecretScript = name: secret: let
    secretPath = getSecretPath name;
    targetDir = escapeShellArg (dirOf secretPath);
    targetI = escapeShellArg (secretPath + ".i");
    target = escapeShellArg secretPath;
  in ''
    mkdir -p ${targetDir}
    truncate -s 0 ${targetI}
    ${optionalString (secret.owner != "root") ''
      chown ${escapeShellArg secret.owner} ${targetI}
    ''}
    ${optionalString (secret.group != users.users."root".group) ''
      chgrp ${escapeShellArg secret.group} ${targetI}
    ''}
    ${concatStringsSep "\n" (map (source: ''
      ${pkgs.sops}/bin/sops --decrypt ${optionalString (source.outputType != null) "--output-type ${escapeShellArg source.outputType}"} ${optionalString (source.key != null) "--extract ${escapeShellArg source.key}"} ${escapeShellArg source.file} >>${targetI}
    '') secret.sources)}
    chmod ${escapeShellArg secret.mode} ${targetI}
    mv -Tf ${targetI} ${target}
  '';

  mkSecretsScript = secrets: ''
    ${optionalString (config.sops.ageKeyFile != null) ''
      export SOPS_AGE_KEY_FILE=${escapeShellArg config.sops.ageKeyFile}
    ''}
    export SOPS_GPG_EXEC=${pkgs.gnupg}/bin/gpg

    ${concatStringsSep "\n" (mapAttrsToList mkSecretScript secrets)}
  '';
in
{
  options = {
    sops = {
      activationPhases = self.lib.activationPhasesOption;

      secrets = secretsOption;

      ageKeyFile = mkOption {
        type = types.nullOr types.path;
        description = ''
          The location of the age private key(s) to load.
        '';
        default = null;
        example = /root/keys.txt;
      };
    };
  };

  config = mkIf (cfg.secrets != {}) {
    assertions = mapAttrsToList (name: secret: {
      assertion = hasAttr secret.activationPhase cfg.activationPhases;
      message = "The activation phase ${strings.escapeNixIdentifier secret.activationPhase} used by sops.secrets.${strings.escapeNixIdentifier name} is not defined.";
    }) cfg.secrets;

    sops.activationPhases = {
      "forRoot" = { before = [ "users" ]; };
      "forUser" = { after = [ "users" "groups" ]; };
    };

    system.activationScripts = mkMerge [
      (mkMerge (self.lib.mapActivationPhaseSecrets ({ activationPhase, secrets }: mkMerge [
        {
          ${activationPhase.activationScriptsKey} = stringAfter ([ "specialfs" "sopsBootSecrets" ] ++ activationPhase.after) (mkSecretsScript secrets);
        }
        (mkMerge (map (dep: {
          ${dep}.deps = [ activationPhase.activationScriptsKey ];
        }) activationPhase.before))
      ]) cfg))
    ];
  };
}
