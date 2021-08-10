{ self, pkgs, ...}:
{
  name = "sops-nixos-simple";

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

    sops.secrets."test" = {
      sources = [
        { file = sopsFile; key = ''["test"]''; }
      ];
    };
    sops.ageKeyFile = privateKey;

    environment.etc."foo".source = config.sops.secrets."test".target;
  };

  testScript = ''
    machine.wait_for_unit('default.target')
    machine.succeed('test "$(< /etc/foo)" = foo')
  '';
}
