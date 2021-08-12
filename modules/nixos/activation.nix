{ self, config, lib, pkgs, ... }: with lib;
let
  inherit (config) users;
  inherit (import ./lib.nix { inherit config lib; })
    generationStoragePath
    getSecretStoragePath;

  cfg = config.sops;

  # Create a package that contains all store symbolic links.
  linkPkg = pkgs.linkFarm "sops-secret-links" (mapAttrsToList (name: secret: {
    inherit name;
    path = getSecretStoragePath "secrets-${name}";
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

  mkSecretScript = { name, secret }: let
    secretStoragePath = getSecretStoragePath "secrets-${name}";
    targetDir = escapeShellArg (dirOf secretStoragePath);
    targetI = escapeShellArg (secretStoragePath + ".i");
    target = escapeShellArg secretStoragePath;
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

    ${concatStringsSep "\n" (mapAttrsToList (name: secret: mkSecretScript { inherit name secret; }) secrets)}
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

    systemd.tmpfiles.rules = [
      "z /run/keys/sops 0750 root ${builtins.toString config.ids.gids.keys} -"
      "z /run/keys/sops 0750 root ${builtins.toString config.ids.gids.keys} -"
      "e /run/keys/sops - - - 0 -"
      "x ${builtins.toString generationStoragePath} - - - - -"
    ];
  };
}
