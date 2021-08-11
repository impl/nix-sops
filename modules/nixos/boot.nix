{ self, config, lib, pkgs, ... }: with lib;
let
  inherit (import ./lib.nix { inherit config lib; })
    getSecretStoragePath
    initScript;

  cfg = config.sops;

  secretsOption = self.lib.mkSecretsOption {
    extraModules = toList ({ name, ... }: {
      config = {
        target = getSecretStoragePath "boot-secrets-${name}";
      };
    });
  };

  mkSecretScript = secret: let
    target = escapeShellArg (secret.target);
  in ''
    truncate -s 0 ${target}
    ${concatStringsSep "\n" (map (source: ''
      ${pkgs.sops}/bin/sops --decrypt ${optionalString (source.key != null) "--extract ${escapeShellArg source.key}"} ${escapeShellArg source.file} >>${target}
    '') secret.sources)}
    chmod ${escapeShellArg secret.mode} ${target}
  '';

  initrdSecretAppenderWrapper = pkgs.writeShellScript "sops-append-initrd-secrets-wrapper" ''
    ${initScript}

    ${optionalString (config.sops.ageKeyFile != null) ''
      export SOPS_AGE_KEY_FILE=${escapeShellArg config.sops.ageKeyFile}
    ''}
    export SOPS_GPG_EXEC=${pkgs.gnupg}/bin/gpg

    ${concatStringsSep "\n" (mapAttrsToList (name: secret: mkSecretScript secret) cfg.bootSecrets)}

    exec ${config.system.build.initialRamdiskSecretAppender}/bin/append-initrd-secrets "$@"
  '';
in
{
  options = {
    sops.bootSecrets = secretsOption;
  };

  config = mkIf (cfg.bootSecrets != {}) {
    system.extraSystemBuilderCmds = ''
      # Replace the default append-initrd-secrets wrapper script with the SOPS helper.
      test -x $out/append-initrd-secrets && ln -snf ${initrdSecretAppenderWrapper} $out/append-initrd-secrets
    '';
  };
}
