{ config, pkgs, lib, ... }:

with pkgs;
with lib;
with builtins;

let
  cfg = config.targetImage;
in
{
  options = {
    targetImage = {
      tarball = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "path-to/rootfs.tar";
        description = ''
        '';
      };
      config = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "path-to/config";
        description = ''
        '';
      };
    };
  };

  config = {
    environment.files.installer = {
      root = "/installer";
      files = {
        "nixos-image".source = cfg.tarball + "/nixos.tar.gz";
        "config" = {
            mode = "a+rwx";
            user = "root";
            source = cfg.config + "/config";
        };
      };
    };
  # bootloader.
  boot = {
    # Clean /tmp on boot
    cleanTmpDir = true;

    # See console messages during early boot.
    initrd = {
      kernelModules = [ ];
    };

    # Use the systemd-boot EFI boot loader.
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };

    # Increase the amount of inotify watchers
    # Note that inotify watches consume 1kB on 64-bit machines.
    kernel = {
      sysctl = {
        "fs.inotify.max_user_watches"   = 1048576;   # default:  8192
        "fs.inotify.max_user_instances" =    1024;   # default:   128
        "fs.inotify.max_queued_events"  =   32768;   # default: 16384
        "vm.max_map_count"              =  262144;
      };
    };

    kernelParams = [
      # Disable console blanking after being idle.
      "consoleblank=0"
      # Required for zfs
      "zfs_force=1"
    ];

    supportedFilesystems = [ "zfs" ];

    zfs = {
      forceImportRoot = false;
      forceImportAll = false;
    };
  };

    ## Default root password is "root"
    users.mutableUsers = false;
    users.extraUsers.root.hashedPassword = "$6$cSUnFL6MbD34$BaS0NLN1KCddegCaTKDMCc1D21Pdge9gFz5tr65U0KgNOgtrEoAGuVnelaPIuEb7iC0FOWE7HUG6NV2b2yN8s/";

  environment.systemPackages = with pkgs; [
    coreutils
    gptfdisk
    cryptsetup
    iproute
    gawk
    zfs
    parted
    dosfstools
    e2fsprogs
    utillinux
    gnugrep
    dhcpcd
    gnutar
    xz
    gzip
    kmod
    config.systemd.package
    config.system.build.nixos-generate-config
    config.system.build.nixos-enter
  ];

    # override installation-cd-base and enable wpa and sshd start at boot
    systemd.services.wpa_supplicant.wantedBy = lib.mkForce [ "multi-user.target" ];
    systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
    systemd.services.minigetty.enable = false;
    systemd.services.installer = {
      # yeah, I know that's not how it's done. path was too long. it's fixed in 19.03
      environment.PATH = lib.mkForce "/root/bin:/run/wrappers/bin:/root/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/etc/profiles/per-user/root/bin";
      description = "Self-bootstrap a NixOS installation";
      after = [ "getty.target" "nscd.service" ];
      conflicts = [ "getty@tty1.service" ];
      wantedBy = [ "multi-user.target" ];
      script = builtins.readFile ./install-script.sh;
      serviceConfig = {
        Type="oneshot";
        RemainAfterExit="yes";
        StandardInput="tty-force";
        StandardOutput="inherit";
        StandardError="inherit";
        TTYReset="yes";
        TTYVHangup="yes";
      };
    };
  };
}
