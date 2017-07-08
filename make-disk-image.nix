{ pkgs
, lib

, # The NixOS configuration to be installed onto the disk image.
  config

, # The size of the disk, in megabytes.
  diskSize

  # The files and directories to be placed in the target file system.
  # This is a list of attribute sets {source, target} where `source'
  # is the file system object (regular file or directory) to be
  # grafted in the file system at path `target'.
, contents ? []

, labelType ? "gpt"

, # Whether the disk should be partitioned (with a single partition
  # containing the root filesystem) or contain the root filesystem
  # directly.
  partitions ? [
    {type = "efi"; size = 200; label = "ESP"; mount = "/boot";}
    {type = "ext4"; label = "NIXOS_IMG_ROOT"; mount = "/";}
  ]

  # Whether to invoke switch-to-configuration boot during image creation
, installBootLoader ? true

, # The initial NixOS configuration file to be copied to
  # /etc/nixos/configuration.nix.
  configFile ? null

, # Shell code executed after the VM has finished.
  postVM ? ""

, name ? "nixos-disk-image"

  # This prevents errors while checking nix-store validity, see
  # https://github.com/NixOS/nix/issues/1134
, fixValidity ? true

, format ? "raw"
}:

with lib;

let
  parts = (foldl
      ({cur, curOff, parts}: part: {
        parts = parts ++ [(part // rec {
          num = cur;
          offset = curOff;
          deviceName = "vda${toString num}";
          devicePath = "/dev/${deviceName}";
        })];
        cur = cur + 1;
        # Will fail to evaluate if a partition with size null is not the last
        curOff = curOff + part.size;
      })
      {cur = 1; curOff = 1; parts = [];}
      partitions).parts;

  partsMountOrder = (toposort (a: b: hasPrefix a.mount b.mount) parts).result;
  partsUmountOrder = (toposort (a: b: hasPrefix b.mount a.mount) parts).result;

  fsTypes = {
    ext4 = {
      mkfs = {label, devicePath, ...}: "mkfs.ext4 ${devicePath} -L ${label}";
      gptType = "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
    };
    efi = {
      mkfs = {label, devicePath, ...}: "mkdosfs -F 32 ${devicePath} -n ${label}";
      gptType = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
    };
  };

  forEachFs = fn: concatMapStringsSep "\n" fn parts;

  partitionCommands = ''
    sfdisk /dev/vda <<EOF
    label: gpt
  '' + forEachFs ({type, size ? null, num, label ? "", offset, ...}:
            "/dev/vda${toString num} : "
          + "start=${toString offset}M, "
          + optionalString (size != null) "size=${toString size}M, "
          + "type=${fsTypes.${type}.gptType}, "
          + optionalString (label != "") "name=${label}, "
          + "\n")
    + "EOF";

  rootPart = let num = (findFirst (x: x.mount or "" == "/") (throw "No root disk") parts).num;
    in "/dev/vda${toString num}";

  makeFilesystems = forEachFs (fs: fsTypes.${fs.type}.mkfs fs);

  mountFilesystems = concatMapStringsSep "\n"
    ({num, mount, ...}: ''
        mkdir -p /mnt/${mount}
        mount /dev/vda${toString num} /mnt/${mount}
      '')
    partsMountOrder;

  unmountFilesystems = concatMapStringsSep "\n"
    ({num, mount, ...}: ''
        umount /mnt/${mount}
      '')
    partsUmountOrder;

in pkgs.vmTools.runInLinuxVM (
  pkgs.runCommand name
    { preVM =
        ''
          mkdir $out
          diskImage=$out/nixos.${if format == "qcow2" then "qcow2" else "img"}
          ${pkgs.vmTools.qemu}/bin/qemu-img create -f ${format} $diskImage "${toString diskSize}M"
          mv closure xchg/
        '';
      buildInputs = with pkgs; [ utillinux perl e2fsprogs parted rsync dosfstools strace ];

      # I'm preserving the line below because I'm going to search for it across nixpkgs to consolidate
      # image building logic. The comment right below this now appears in 4 different places in nixpkgs :)
      # !!! should use XML.
      sources = map (x: x.source) contents;
      targets = map (x: x.target) contents;

      exportReferencesGraph =
        [ "closure" config.system.build.toplevel ];
      inherit postVM;
      memSize = 1024;
    }
    ''
      export PATH=${pkgs.nix}/bin:$PATH
      ${partitionCommands}
      mkdir /dev/block
      for blk in /sys/class/block/vda?* ; do
        . $blk/uevent
        mknod /dev/$(basename $blk) b $MAJOR $MINOR
        # Expected by bootctl
        mknod /dev/block/$MAJOR:$MINOR b $MAJOR $MINOR
      done
      rootPart=${rootPart}

      # Create filesystems and mount them
      ${makeFilesystems}
      ${mountFilesystems}

      # Register the paths in the Nix database.
      printRegistration=1 perl ${pkgs.pathsFromGraph} /tmp/xchg/closure | \
          ${config.nix.package.out}/bin/nix-store --load-db --option build-users-group ""

      #$printRegistration}/bin/nix-print-registration /tmp/xchg/closure > /tmp/db
      #</tmp/db ${config.nix.package.out}/bin/nix-store --load-db --option build-users-group ""

      ${optionalString fixValidity ''
        echo "Fixing validity"
        # Add missing size/hash fields to the database. FIXME:
        # exportReferencesGraph should provide these directly.
        count=$(${config.nix.package.out}/bin/nix-store --verify --check-contents --option build-users-group "" 2>&1 | wc -l)
        printf -- "Made %d changes\n" "$count"
      ''}

      #find / -not -path '/sys*' -not -path '/proc/*'

      # Install the closure onto the image
      USER=root ${config.system.build.nixos-install}/bin/nixos-install \
        --closure ${config.system.build.toplevel} \
        --no-channel-copy \
        --no-root-passwd \
        ${optionalString (!installBootLoader) "--no-bootloader"} || failed=1

      df -h
      [[ -z $failed ]] # Die now if we failed

      mkdir -p /mnt/boot/EFI/BOOT
      cp ${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootx64.efi /mnt/boot/EFI/BOOT/BOOTX64.EFI

      find /mnt/boot

      # Install a configuration.nix.
      mkdir -p /mnt/etc/nixos
      ${optionalString (configFile != null) ''
        cp ${configFile} /mnt/etc/nixos/configuration.nix
      ''}

      # Remove /etc/machine-id so that each machine cloning this image will get its own id
      rm -f /mnt/etc/machine-id

      # Copy arbitrary other files into the image
      # Semi-shamelessly copied from make-etc.sh. I (@copumpkin) shall factor this stuff out as part of
      # https://github.com/NixOS/nixpkgs/issues/23052.
      set -f
      sources_=($sources)
      targets_=($targets)
      set +f

      for ((i = 0; i < ''${#targets_[@]}; i++)); do
        source="''${sources_[$i]}"
        target="''${targets_[$i]}"

        if [[ "$source" =~ '*' ]]; then

          # If the source name contains '*', perform globbing.
          mkdir -p /mnt/$target
          for fn in $source; do
            rsync -a --no-o --no-g "$fn" /mnt/$target/
          done

        else

          mkdir -p /mnt/$(dirname $target)
          if ! [ -e /mnt/$target ]; then
            rsync -a --no-o --no-g $source /mnt/$target
          else
            echo "duplicate entry $target -> $source"
            exit 1
          fi
        fi
      done

      ${unmountFilesystems}

      # Make sure resize2fs works. Note that resize2fs has stricter criteria for resizing than a normal
      # mount, so the `-c 0` and `-i 0` don't affect it. Setting it to `now` doesn't produce deterministic
      # output, of course, but we can fix that when/if we start making images deterministic.
      #  tune2fs -T now -c 0 -i 0 $rootPart
    ''
)
