{ config, lib }: with lib;
let
  cfg = config.sops;

  generationStoragePath = /run/keys/sops + "/${config.system.build.toplevel.name}";
in
{
  inherit generationStoragePath;

  getSecretStoragePath = name: generationStoragePath + "/${strings.sanitizeDerivationName name}";
}
