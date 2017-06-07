{
  storageSize ? 1000,
  rootSize ? 3072
}:
let
  pkgs = import <nixpkgs> {};
  inherit (pkgs) stdenv runCommand vmTools;
  vmConfig = (import <nixpkgs/nixos/lib/eval-config.nix> {
    inherit (pkgs) system;
    modules = [ <nixpkgs/nixos/modules/installer/tools/tools.nix> ];
  }).config;
  destConfig = (import <nixpkgs/nixos/lib/eval-config.nix> {
    inherit (pkgs) system;
    modules = [ ./barony-bootable.nix ./barony-config.nix ];
  }).config;

in
(vmTools.runInLinuxVM (
runCommand "barony-writable-disk" {
  buildInputs = with pkgs; [
    utillinux
    dosfstools
    e2fsprogs
    strace
    #eudev
    systemd
  ] ++ vmConfig.environment.systemPackages ++
  destConfig.environment.systemPackages;
  QEMU_OPTS = "-drive if=virtio,format=raw,file=$out/root.img";
  partitioned = true;
  preVM = ''
    mkdir -p $out
    dd if=/dev/zero of=$out/root.img bs=1M count=1 seek=${toString (3 + storageSize + rootSize)}
  '';
} ''
  #!${stdenv.shell}
  makeNodes() {
    for dev in /sys/class/block/* ; do (
      . $dev/uevent
      rm -f /dev/$DEVNAME
      mknod /dev/$DEVNAME b $MAJOR $MINOR
    )
    done
  }
  set -x
  #udevd --daemon
  #udevadm trigger --action=add
  #udevadm settle
  ${pkgs.systemd}/lib/systemd/systemd-udevd &
  sleep 1
  udevadm trigger --action=add
  udevadm settle

  ls /dev/
  #makeNodes

  sfdisk /dev/vdb <<EOF
  label: dos
  label-id: 0x4241524f

  size=${toString (storageSize * 2048)} type=0b
  size=${toString (rootSize * 2048)} type=83 bootable
  EOF
  blkid /dev/vdb
  false

  #makeNodes

  mkfs.vfat -n BARONYSTOR /dev/vdb1
  mkfs.ext4 -L barony-root /dev/vdb2


  mkdir /mnt
  mount /dev/vdb2 /mnt
  nixos-generate-config --root /mnt
  cat /mnt/etc/nixos/*
  cp ${./barony-config.nix} /mnt/etc/nixos/barony-config.nix
  cat > /mnt/etc/nixos/configuration.nix <<EOF
  { imports = [ ./barony-config.nix ./hardware-configuration.nix ]; }
  EOF
  export NIX_PATH=nixpkgs=${./.}
  strace -e file grub-install -v /dev/vda
  nixos-install
''
))
