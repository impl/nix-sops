# SPDX-FileCopyrightText: 2003-2021 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-FileCopyrightText: 2021-2024 Noah Fontes
#
# SPDX-License-Identifier: MIT
#
# Portions of this file are derived from the system tests for NixOS. See
# <https://github.com/NixOS/nixpkgs/blob/c6aa7bdae0143c41043968a3abd9a9727a6cdf5a/nixos/tests/hibernate.nix>
# for more information.

f: args@{ inputs, pkgs, system, ... }: let
  mkTest = t@{ name, preInstallScript ? "", postInstallScript ? "", testScript, ... }: let
    profiles = { "system" = {}; }
      // (t.profiles or {})
      // (if t ? machine then { "system" = t.machine; } else {});

    installedConfigs = builtins.mapAttrs (name: machine: inputs.nixpkgs.lib.nixosSystem {
      inherit (pkgs.stdenv.hostPlatform) system;
      modules = [
        ({ modulesPath, lib, ... }: with lib; {
          imports = [
            "${modulesPath}/testing/test-instrumentation.nix"
            "${modulesPath}/profiles/qemu-guest.nix"
            "${modulesPath}/profiles/minimal.nix"
          ];

          hardware.enableAllFirmware = mkVMOverride false;
          documentation.nixos.enable = false;

          boot.loader.timeout = mkVMOverride 0;
          boot.loader.grub = mkVMOverride {
            enable = true;
            device = "/dev/vda";
            configurationName = name;
          };

          fileSystems = {
            "/" = mkVMOverride {
              device = "/dev/vda2";
            };
            "/nix/store" = mkVMOverride {
              device = "store";
              fsType = "9p";
              options = [ "trans=virtio" "version=9p2000.L" "cache=loose" ];
              neededForBoot = true;
            };
          };
          swapDevices = mkVMOverride [
            {
              device = "/dev/vda1";
            }
          ];
        })
        machine
      ];
    }) profiles;

    installedSystems = builtins.mapAttrs (name: installedConfig: installedConfig.config.system.build.toplevel) installedConfigs;
  in
  {
    inherit name;

    nodes = {
      installer = { lib, modulesPath, ... }: with lib; {
        imports = [
          "${modulesPath}/profiles/installation-device.nix"
          "${modulesPath}/profiles/base.nix"
        ];

        # Installation media sets this, but it just produces warnings in tests.
        users.users.root.initialHashedPassword = mkForce null;

        nix.settings.substituters = mkForce [];
        nix.extraOptions = ''
          hashed-mirrors =
          connect-timeout = 1
        '';

        boot.initrd.systemd.enable = true;
        testing.initrdBackdoor = false;

        virtualisation.diskSize = 8 * 1024;
        virtualisation.diskImage = "./target.qcow2";
        virtualisation.emptyDiskImages = [
          # Small root disk for installer
          512
        ];
        virtualisation.rootDevice = "/dev/vdb";
        virtualisation.fileSystems."/".autoFormat = true;
        virtualisation.additionalPaths = attrValues installedSystems;
      };

      target = {
        virtualisation.diskSize = 8 * 1024;
        virtualisation.diskImage = "./target.qcow2";
        virtualisation.useBootLoader = true;
        virtualisation.useDefaultFilesystems = false;

        virtualisation.fileSystems."/" = {
          device = "/dev/vda2";
          fsType = "ext4";
        };

        virtualisation.qemu.options = [
          "-virtfs local,path=/nix/store,security_model=none,mount_tag=store"
        ];
      };
    };

    testScript = ''
      # Bootstrap machine.
      installer.start()
      installer.wait_for_unit('default.target')
      installer.succeed(
        'flock /dev/vda parted --script /dev/vda -- mklabel msdos mkpart primary linux-swap 1M 1024M mkpart primary ext2 1024M -1s',
        'udevadm settle',
        'mkfs.ext3 -L nixos /dev/vda2',
        'mount LABEL=nixos /mnt',
        'mkswap /dev/vda1 -L swap',
        'mkdir -p /mnt/nix/store',
        'mount --bind /nix/store /mnt/nix/store',
        'nix-store --dump-db | nix-store --store /mnt --load-db',
      )

      ${preInstallScript}

      # Install NixOS onto the primary drive.
      installer.succeed(
        ${with pkgs.lib; concatStringsSep "\n" (mapAttrsToList (name: installedSystem: ''
          "nix-env --store /mnt --extra-substituters 'auto?trusted=1' -p ${escapeShellArg "/mnt/nix/var/nix/profiles/${name}"} --set ${installedSystem}",
        '') (filterAttrs (name: installedSystem: name != "system") installedSystems))}
      )
      installer.succeed('nixos-install -vv --root /mnt --system ${installedSystems."system"} --no-root-passwd')
      installer.succeed('sync')

      ${postInstallScript}

      installer.shutdown()

      # Reboot, hope everything activates!
      target.state_dir = installer.state_dir
      target.start()

      ${testScript}
    '';
  };
in mkTest (if pkgs.lib.isFunction f then f args else f)
