# SPDX-FileCopyrightText: 2021 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

# This test attempts to emulate a nixos-install operation, where an essentially
# unconfigured system is first bootstrapped by a user with a PGP key. The
# bootstrap process installs a permanent age key that is used for future
# activations.
import ./make-installer-test.nix ({ self, pkgs, ... }: let
  # NB: This puts the GnuPG configuration in the Nix store. You almost
  # certainly do not want to do this. Read the documentation before you copy
  # from this file!
  testOnlyPgpKey = pkgs.runCommand "test-only-pgp-key" {} ''
    ${pkgs.gnupg}/bin/gpg --batch --homedir $TMP --gen-key <<EOT
      Key-Type: 1
      Key-Length: 2048
      Subkey-Type: 1
      Subkey-Length: 2048
      Name-Real: NixOS Test
      Name-Email: nixos-test@localhost
      Expire-Date: 0
      %no-protection
    EOT
    ${pkgs.gnupg}/bin/gpg --batch --homedir $TMP --export-secret-keys --armor >$out
  '';
  testOnlyPgpKeyFingerprint = pkgs.runCommand "test-only-pgp-key-fingerprint" {} ''
    ${pkgs.gnupg}/bin/gpg --batch --homedir $TMP --import ${testOnlyPgpKey}
    ${pkgs.gnupg}/bin/gpg --batch --homedir $TMP --list-keys nixos-test@localhost | sed -n -e 'N;s#pub.*\n\s*\(.*\)#\1#p' >$out
  '';
  # NB: This puts your age private key in the Nix store. You almost certainly
  # do not want to do this. Read the documentation before you copy from this
  # file!
  testOnlyAgePrivateKey = pkgs.runCommand "test-only-age-private-key" {} ''
    ${pkgs.age}/bin/age-keygen -o $out
  '';
  testOnlyAgePublicKey = pkgs.runCommand "test-only-age-public-key" {} ''
    ${pkgs.age}/bin/age-keygen -o $out -y ${testOnlyAgePrivateKey}
  '';
  sopsFile = pkgs.runCommand "sops-secrets" {
    "SOPS_AGE_KEY_FILE" = testOnlyAgePrivateKey;
    "SOPS_GPG_EXEC" = "${pkgs.gnupg}/bin/gpg";
  } ''
    # Set up GPG (really only need the public key here).
    mkdir $TMP/.gnupg
    export GNUPGHOME=$TMP/.gnupg
    ${pkgs.gnupg}/bin/gpg --batch --import ${testOnlyPgpKey}

    # This argument will set the YAML key "system" to the content of the age
    # private key for this machine.
    setSystemArg='["system"] '"$(${pkgs.jq}/bin/jq -n --rawfile systemKey ${testOnlyAgePrivateKey} '$systemKey')"

    truncate -s 0 $out
    ${pkgs.sops}/bin/sops --encrypt --in-place --age "$(<${testOnlyAgePublicKey})" --pgp "$(<${testOnlyPgpKeyFingerprint})" $out
    ${pkgs.sops}/bin/sops --set "$setSystemArg" $out
    ${pkgs.sops}/bin/sops --set '["test"] ${builtins.toJSON "foo"}' $out
  '';
in
{
  name = "sops-nixos-install";

  machine = { config, ... }: {
    imports = [ self.nixosModule ];

    sops.ageKeySecretSource = {
      file = sopsFile;
      key = ''["system"]'';
    };

    sops.secrets."test" = {
      sources = [
        { file = sopsFile; key = ''["test"]''; }
      ];
    };

    environment.etc."foo".source = config.sops.secrets."test".target;
  };

  preInstallScript = ''
    # Import PGP key for installer. Using a bind mount ensures the key will not
    # be copied to the target drive.
    machine.succeed(
      '${pkgs.gnupg}/bin/gpg --batch --import ${testOnlyPgpKey}',
      'mkdir -p /mnt/root/.gnupg',
      'mount --bind /root/.gnupg /mnt/root/.gnupg',
    )
  '';

  postInstallScript = ''
    # Will hang reboot if not explicitly terminated.
    machine.succeed('${pkgs.gnupg}/bin/gpgconf --kill gpg-agent')
  '';

  testScript = ''
    machine.wait_for_unit('default.target')
    machine.succeed('test "$(</etc/foo)" = foo')
  '';
})
