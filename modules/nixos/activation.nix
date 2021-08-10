{ self, config, lib, pkgs, ... }: with lib;
let
  inherit (config) users;
  inherit (import ./lib.nix { inherit config lib; })
    generationStoragePath
    getSecretStoragePath
    initScript;

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
    target = escapeShellArg (getSecretStoragePath "secrets-${name}");
  in ''
    truncate -s 0 ${target}
    ${optionalString (secret.owner != "root") ''
      chown ${escapeShellArg secret.owner} ${target}
    ''}
    ${optionalString (secret.group != users.users."root".group) ''
      chgrp ${escapeShellArg secret.group} ${target}
    ''}
    ${concatStringsSep "\n" (map (source: ''
      ${pkgs.sops}/bin/sops --decrypt ${optionalString (source.key != null) "--extract ${escapeShellArg source.key}"} ${escapeShellArg source.file} >>${target}
    '') secret.sources)}
    chmod ${escapeShellArg secret.mode} ${target}
  '';

  mkSecretsScript = secrets: ''
    ${optionalString (config.sops.ageKeyFile != null) ''
      export SOPS_AGE_KEY_FILE=${escapeShellArg config.sops.ageKeyFile}
    ''}
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
          The runtime location to store secret data. This path will be mounted
          as a ramfs filesystem.
        '';
        default = /run/sops;
        example = /tmp/secrets;
      };

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
      "forRoot" = { after = [ "specialfs" ]; before = [ "users" ]; };
      "forUser" = { after = [ "specialfs" "users" "groups" ]; };
    };

    system.activationScripts = mkMerge [
      {
        sopsInit = stringAfter [ "specialfs" ] initScript;
      }
      (mkMerge (self.lib.mapActivationPhaseSecrets ({ activationPhase, secrets }: mkMerge [
        {
          ${activationPhase.activationScriptsKey} = stringAfter ([ "sopsInit" ] ++ activationPhase.after) (mkSecretsScript secrets);
        }
        (mkMerge (map (dep: {
          ${dep}.deps = [ activationPhase.activationScriptsKey ];
        }) activationPhase.before))
      ]) cfg))
    ];

    systemd.tmpfiles.rules = [
      "z ${escapeShellArg cfg.storagePath} 0750 root ${toString config.ids.gids.keys} -"
      "z ${escapeShellArg (cfg.storagePath + "/*")} 0750 root ${toString config.ids.gids.keys} -"
      "e ${escapeShellArg cfg.storagePath} - - - 0 -"
      "x ${escapeShellArg generationStoragePath} - - - - -"
    ];
  };
}
