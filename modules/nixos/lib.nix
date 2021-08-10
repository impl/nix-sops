{ config, lib }: with lib;
let
  cfg = config.sops;

  generationStoragePath = /. + cfg.storagePath + "/${config.system.build.toplevel.name}";
in
{
  inherit generationStoragePath;

  getSecretStoragePath = name: generationStoragePath + "/${strings.sanitizeDerivationName name}";

  initScript = let
    storagePath = escapeShellArg cfg.storagePath;
  in ''
    oldSopsFsType=$(findmnt --noheadings --output FSTYPE ${storagePath} || true)
    if [ -z "$oldSopsFsType" ]; then
      mkdir -p ${storagePath}
      mount -t ramfs -o nosuid,nodev none ${storagePath}
    elif [ "$oldSopsFsType" != ramfs ]; then
      printf "SOPS storage path %s is already mounted, but has type %s. Won't remount.\n" ${storagePath} "$oldSopsFsType" >&2
      exit 1
    fi

    chmod 0750 ${storagePath}
    mkdir -p ${escapeShellArg generationStoragePath}
    chmod 0750 ${escapeShellArg generationStoragePath}
  '';
}
