# SPDX-FileCopyrightText: 2021-2024 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

# This test checks that an existing NixOS install can be activated with a new
# configuration that contains SOPS secrets, and then that the bootstrapped
# machine key can be rotated by our own machinery.
import ./make-installer-test.nix ({ self, pkgs, ... }: let
  # NB: This puts your age private key in the Nix store. You almost certainly
  # do not want to do this. Read the documentation before you copy from this
  # file!
  testOnlyBootstrapAgePrivateKey = pkgs.runCommand "test-only-bootstrap-age-private-key" {} ''
    ${pkgs.age}/bin/age-keygen -o $out
  '';
  testOnlyBootstrapAgePublicKey = pkgs.runCommand "test-only-bootstrap-age-public-key" {} ''
    ${pkgs.age}/bin/age-keygen -o $out -y ${testOnlyBootstrapAgePrivateKey}
  '';
in
{
  name = "sops-nixos-activation";

  profiles = let
    # NB: This puts your age private key in the Nix store. You almost certainly
    # do not want to do this. Read the documentation before you copy from this
    # file!
    testOnlyAgePrivateKey = pkgs.runCommand "test-only-age-private-key" {} ''
      ${pkgs.age}/bin/age-keygen -o $out
    '';
    testOnlyAgePublicKey = pkgs.runCommand "test-only-age-public-key" {} ''
      ${pkgs.age}/bin/age-keygen -o $out -y ${testOnlyAgePrivateKey}
    '';

    # Initial bootstrapping file.
    initialSopsFile = pkgs.runCommand "initial-sops-secrets" { "SOPS_AGE_KEY_FILE" = testOnlyAgePrivateKey; } ''
      truncate -s 0 $out
      ${pkgs.sops}/bin/sops --encrypt --in-place \
        --age "$(<${testOnlyBootstrapAgePublicKey})" \
        --age "$(<${testOnlyAgePublicKey})" \
        $out
      ${pkgs.sops}/bin/sops --set '["test"] ${builtins.toJSON "foo"}' $out
    '';

    # Reconfigured file without bootstrap key.
    reconfiguredSopsFile = pkgs.runCommand "reconfigured-sops-secrets" { "SOPS_AGE_KEY_FILE" = testOnlyAgePrivateKey; } ''
      cp --no-preserve=mode ${initialSopsFile} $out
      ${pkgs.sops}/bin/sops --rotate --in-place --rm-age "$(<${testOnlyBootstrapAgePublicKey})" $out
      ${pkgs.sops}/bin/sops --set '["test"] ${builtins.toJSON "bar"}' $out
    '';

    mkConfig = sopsFile: { config, ... }: {
      imports = [ self.nixosModules.default ];

      sops.secrets."test" = {
        sources = [
          { file = sopsFile; key = ''["test"]''; }
        ];
      };
      sops.ageKeyFile = testOnlyAgePrivateKey;

      environment.etc."foo".source = config.sops.secrets."test".target;
    };
  in
  {
    "initial" = mkConfig initialSopsFile;
    "reconfigured" = mkConfig reconfiguredSopsFile;
  };

  testScript = ''
    # Add temporary bootstrapping key.
    target.wait_for_unit('default.target')
    target.succeed(
      'mkdir -p /root/.config/sops',
      'ln -s ${testOnlyBootstrapAgePrivateKey} /root/.config/sops/keys.txt',
    );

    # Apply initial configuration.
    target.succeed('/nix/var/nix/profiles/initial/bin/switch-to-configuration switch')

    # Bootstrap directory should no longer be required.
    target.succeed('rm -fr /root/.config/sops');

    # Make sure our file got put in the right place.
    target.succeed('test "$(</etc/foo)" = foo')
    orig = target.succeed('readlink -ne /etc/foo')

    # Reboot to test boot-time activation.
    target.shutdown()
    target.wait_for_unit('default.target')
    target.succeed('test "$(</etc/foo)" = foo')

    # Apply a new configuration with an updated value.
    target.succeed('/nix/var/nix/profiles/reconfigured/bin/switch-to-configuration switch')

    # File content should have changed.
    target.succeed('test "$(</etc/foo)" = bar')
    updated = target.succeed('readlink -ne /etc/foo')
    assert orig != updated
  '';
})
