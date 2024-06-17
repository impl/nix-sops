# SPDX-FileCopyrightText: 2021-2024 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{ self, pkgs, ...}:
{
  name = "sops-nixos-boot-secrets";

  nodes.machine = let
    # NB: This puts your age private key in the Nix store. You almost certainly
    # do not want to do this. Read the documentation before you copy from this
    # file!
    testOnlyAgePrivateKey = pkgs.runCommand "test-only-age-private-key" {} ''
      ${pkgs.age}/bin/age-keygen -o $out
    '';
    testOnlyAgePublicKey = pkgs.runCommand "test-only-age-public-key" {} ''
      ${pkgs.age}/bin/age-keygen -o $out -y ${testOnlyAgePrivateKey}
    '';
    sopsFile = pkgs.runCommand "sops-secrets" { "SOPS_AGE_KEY_FILE" = testOnlyAgePrivateKey; } ''
      truncate -s 0 $out
      ${pkgs.sops}/bin/sops --encrypt --in-place --age "$(<${testOnlyAgePublicKey})" $out
      ${pkgs.sops}/bin/sops --set '["test"] ${builtins.toJSON "foo"}' $out
    '';
  in { config, ... }: {
    imports = [ self.nixosModules.default ];

    sops.bootSecrets."/foo" = {
      sources = [
        { file = sopsFile; key = ''["test"]''; }
      ];
    };
    sops.ageKeyFile = testOnlyAgePrivateKey;

    virtualisation.useBootLoader = true;

    boot.loader.timeout = 0;
    boot.loader.grub = {
      enable = true;
    };
  };

  testScript = ''
    machine.wait_for_unit('default.target')
  '';
}
