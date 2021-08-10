{ self, lib, ... }: with lib;
let
  capitalize = s: let
    len = builtins.stringLength s;
    first = substring 0 1 s;
    rest = substring 1 (len - 1) s;
  in "${toUpper first}${rest}";
in
{
  activationPhaseType = types.submodule ({ name, ... }: {
    options = {
      activationScriptsKey = mkOption {
        type = types.str;
        description = ''
          The key used in the activation script builder for this phase.
        '';
      };
      after = mkOption {
        type = types.listOf types.str;
        description = ''
          The dependencies to determine ordering for the activation script.
        '';
        default = [];
        example = [ "specialfs" ];
      };
      before = mkOption {
        type = types.listOf types.str;
        description = ''
          Other activation script dependencies that should run after this
          secret is in place.
        '';
        default = [];
        example = [ "users" ];
      };
    };

    config = {
      activationScriptsKey = "sopsInstall${capitalize name}";
    };
  });

  activationPhasesOption = mkOption {
    type = types.attrsOf self.options.activationPhaseType;
    description = "The available activation phases for secrets.";
    default = {};
    example = literalExample ''
      {
        "custom" = {
          after = [ "specialfs" ];
          before = [ "users" ];
        };
      }
    '';
  };

  secretSourceType = types.submodule {
    options = {
      file = mkOption {
        type = types.path;
        description = "Path to the SOPS file to read the secret from.";
      };
      key = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The key of the document tree generated from the file to load. If not
          specified, the entire document tree will be used. The key should be
          specified using the Python dictionary format as described in the SOPS
          documentation.
        '';
        example = ''["secrets"][1]'';
      };
    };
  };

  mkSecretType = { hasActivationPhase ? true, extraModules ? [] }: types.submoduleWith {
    modules = toList {
      options = {
        target = mkOption {
          type = types.path;
          readOnly = true;
          description = ''
            The store path containing the symbolic link to the eventual secret
            value.
          '';
        };
        sources = mkOption {
          type = types.listOf self.options.secretSourceType;
          default = [];
          description = ''
            The secret sources to load to generate this secret. Each secret
            source will be concatenated into the destination file.
          '';
          example = literalExample ''
            [
              { file = ./secrets-a.yaml; }
              { file = ./scerets-b.yaml; }
            ]
          '';
        };
        mode = mkOption {
          type = types.str;
          default = "0400";
          description = "The file mode for the secret in octal.";
        };
      };
    } ++ optionals hasActivationPhase [
      {
        options = {
          activationPhase = mkOption {
            type = types.str;
            description = "The name of the activation phase for this secret.";
            example = "custom";
          };
        };
      }
    ] ++ extraModules;
    shorthandOnlyDefinesConfig = true;
  };

  mkSecretsOption = { hasActivationPhase ? true, extraModules ? [] }: mkOption {
    type = types.attrsOf (self.options.mkSecretType { inherit hasActivationPhase extraModules; });
    default = {};
    description = ''
      The secrets to write as an attribute set, where each key of the attribute
      set represents a file that should contain secret data, and the value
      describes the secret source.
    '';
  };
}
