# SPDX-FileCopyrightText: 2003-2021 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-FileCopyrightText: 2021-2022 Noah Fontes
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
            version = 2;
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

    nodes.machine = { lib, modulesPath, ... }: with lib; {
      imports = [
        "${modulesPath}/profiles/installation-device.nix"
        "${modulesPath}/profiles/base.nix"
      ];

      nix.binaryCaches = mkForce [];
      nix.extraOptions = ''
        hashed-mirrors =
        connect-timeout = 1
      '';

      virtualisation.diskSize = 8 * 1024;
      virtualisation.emptyDiskImages = [
        # Small root disk for installer
        512
      ];
      virtualisation.bootDevice = "/dev/vdb";
      virtualisation.additionalPaths = attrValues installedSystems;
    };

    testScript = ''
      def create_installed_machine(name):
        new_machine = create_machine({
          "qemuFlags": " ".join([
            "-cpu max",
            "${if system == "x86_64-linux" then "-m 1024" else "-m 768 -enable-kvm -machine virt,gic-version=host"}",
            "-virtfs local,path=/nix/store,security_model=none,mount_tag=store",
          ]),
          "hdaInterface": "virtio",
          "hda": "vm-state-machine/machine.qcow2",
          "name": name,
        })
        driver.machines.append(new_machine)
        return new_machine


      # Bootstrap machine.
      machine.wait_for_unit('default.target')
      machine.succeed(
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
      machine.succeed(
        ${with pkgs.lib; concatStringsSep "\n" (mapAttrsToList (name: installedSystem: ''
          "nix-env --store /mnt --extra-substituters 'auto?trusted=1' -p ${escapeShellArg "/mnt/nix/var/nix/profiles/${name}"} --set ${installedSystem}",
        '') (filterAttrs (name: installedSystem: name != "system") installedSystems))}
      )
      machine.succeed('nixos-install -vv --root /mnt --system ${installedSystems."system"} --no-root-passwd')
      machine.succeed('sync')

      ${postInstallScript}

      machine.shutdown()

      # Reboot, hope everything activates!
      machine = create_installed_machine('${name}-installed')

      ${testScript}
    '';
  };
in mkTest (if pkgs.lib.isFunction f then f args else f)
