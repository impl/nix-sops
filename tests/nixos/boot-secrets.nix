{ self, pkgs, ...}:
{
  name = "sops-nixos-boot-secrets";

  machine = let
    privateKey = pkgs.runCommand "private-key.asc" {} ''
      ${pkgs.age}/bin/age-keygen -o $out
    '';
    publicKey = pkgs.runCommand "public-key" {} ''
      ${pkgs.age}/bin/age-keygen -o $out -y ${privateKey}
    '';
    sopsFile = pkgs.runCommand "secrets.yaml" { "SOPS_AGE_KEY_FILE" = privateKey; } ''
      printf '{}' >$out
      ${pkgs.sops}/bin/sops --encrypt --in-place --age "$(< ${publicKey})" $out
      ${pkgs.sops}/bin/sops --set '["test"] ${builtins.toJSON "foo"}' $out
    '';
  in { config, ... }: {
    imports = [ self.nixosModule ];

    sops.bootSecrets."test" = {
      sources = [
        { file = sopsFile; key = ''["test"]''; }
      ];
    };
    sops.ageKeyFile = privateKey;

    virtualisation.useBootLoader = true;

    boot.loader.timeout = 0;
    boot.loader.grub = {
      enable = true;
      version = 2;
    };
    boot.initrd.secrets = {
      "/key" = config.sops.bootSecrets."test".target;
    };
  };

  testScript = ''
    machine.wait_for_unit('default.target')
  '';
}
