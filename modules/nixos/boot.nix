# SPDX-FileCopyrightText: 2021 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{ self, config, generationPath, lib, pkgs, ... }: with lib;
let
  cfg = config.sops;

  secretsOption = self.lib.mkSecretsOption {
    extraModules = toList ({ name, ... }: {
      options = {
        availableInBootedSystem = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether or not this secret should be copied to the system after
            /run/keys is mounted. If true, the target of this secret will be
            installed and usable during activation as well as at boot.
          '';
        };
      };

      config = {
        target = generationPath + "/boot-secrets-${strings.sanitizeDerivationName name}-${builtins.hashString "sha256" name}";
      };
    });
  };

  mkSecretScript = secret: let
    targetDir = escapeShellArg (dirOf secret.target);
    targetI = escapeShellArg (secret.target + ".i");
    target = escapeShellArg secret.target;
  in ''
    mkdir -p ${targetDir}
    truncate -s 0 ${targetI}
    ${concatStringsSep "\n" (map (source: ''
      ${pkgs.sops}/bin/sops --decrypt ${optionalString (source.key != null) "--extract ${escapeShellArg source.key}"} ${escapeShellArg source.file} >>${targetI}
    '') secret.sources)}
    chmod ${escapeShellArg secret.mode} ${targetI}
    mv -Tf ${targetI} ${target}
  '';

  mkSecretsScript = secrets: ''
    ${optionalString (config.sops.ageKeyFile != null) ''
      export SOPS_AGE_KEY_FILE=${escapeShellArg config.sops.ageKeyFile}
    ''}
    export SOPS_GPG_EXEC=${pkgs.gnupg}/bin/gpg

    ${concatStringsSep "\n" (mapAttrsToList (name: secret: mkSecretScript secret) secrets)}
  '';

  initrdSecretAppenderWrapper = pkgs.writeShellScript "sops-append-initrd-secrets-wrapper" ''
    ${mkSecretsScript cfg.bootSecrets}

    exec ${config.system.build.initialRamdiskSecretAppender}/bin/append-initrd-secrets "$@"
  '';

  secretsAvailableInBootedSystem = filterAttrs (name: secret: secret.availableInBootedSystem) cfg.bootSecrets;
in
{
  options = {
    sops.bootSecrets = secretsOption;
  };

  config = mkMerge [
    (mkIf (cfg.bootSecrets != {}) {
      boot.initrd.secrets = builtins.mapAttrs (name: secret: secret.target) cfg.bootSecrets;

      # Make sure the initrd secrets can be copied by replacing the default
      # append-initrd-secrets wrapper with the SOPS helper.
      system.extraSystemBuilderCmds = ''
        test -x $out/append-initrd-secrets && ln -snf ${initrdSecretAppenderWrapper} $out/append-initrd-secrets
      '';
    })
    (mkIf (secretsAvailableInBootedSystem != {} || cfg.secrets != {}) {
      # Always generate the sopsBootSecrets initializer (even if empty) so that
      # the activation can reference it.
      system.activationScripts."sopsBootSecrets" = stringAfter [ "specialfs" ] (mkSecretsScript secretsAvailableInBootedSystem);
    })
    (mkIf (secretsAvailableInBootedSystem != {}) {
      # Supply the booted-system secrets very early, before any activation
      # runs, by copying out of the initrd.
      boot.initrd.postMountCommands = concatStringsSep "\n" (mapAttrsToList (name: secret: let
        target = escapeShellArg secret.target;
      in ''
        mkdir -p "$(dirname ${target})"
        cp -a ${escapeShellArg (/. + "/${name}")} ${target}
      '') secretsAvailableInBootedSystem);
    })
  ];
}
