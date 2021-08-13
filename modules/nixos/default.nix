# SPDX-FileCopyrightText: 2021 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{ self, config, lib, pkgs, ... }: with lib;
let
  cfg = config.sops;

  versionPkg = pkgs.linkFarm "sops-generation" (self.lib.mkVersionLinkFarmEntries ((attrValues cfg.bootSecrets) ++ (attrValues cfg.secrets)));
  generationPath = "/run/keys/sops/${builtins.baseNameOf versionPkg}";
in
{
  _module.args = { inherit generationPath; };

  imports = [
    ./activation.nix
    ./boot.nix
  ];

  systemd.tmpfiles.rules = [
    "z /run/keys/sops 0750 root ${builtins.toString config.ids.gids.keys} -"
    "z /run/keys/sops 0750 root ${builtins.toString config.ids.gids.keys} -"
    "e /run/keys/sops - - - 0 -"
    "x ${generationPath} - - - - -"
  ];
}
