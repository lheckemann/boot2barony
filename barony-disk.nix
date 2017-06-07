let
pkgs = import <nixpkgs> {};
isoWritableModule = { config, pkgs, lib, ... }:
{
  config = {
    fileSystems."/0-rw" = {
      fsType = "ext4";
      neededForBoot = true;
      device = "/dev/disk/by-label/NIXOS_RW";
    };
    fileSystems."/nix/.rw-store" = lib.mkForce {
      options = [ "bind" ];
      neededForBoot = true;
      device = "/0-rw/nix-store";
    };
    fileSystems."/home" = {
      options = [ "bind" ];
      neededForBoot = true;
      device = "/0-rw/home";
    };
  };
};
config = (import <nixpkgs/nixos/lib/eval-config.nix> {
  inherit (pkgs) system;
  modules = [
    ./barony-config.nix
    isoWritableModule
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
  ];
}).config;
isoImage = config.system.build.isoImage;
in
  with pkgs; stdenv.mkDerivation {
    name = "isoWritable.iso";
    buildInputs = [ e2fsprogs utillinux ];
    buildCommand = ''
      cp ${config.system.build.isoImage}/iso/*.iso $out
      chmod u+w $out
      dd if=/dev/zero of=$out bs=1M count=1024 oflag=append conv=notrunc
      sfdisk --append $out <<EOF
        part3 : type=83
      EOF
      offset_sectors=$(sfdisk -l -q -o start $out | tail -n 1)
      offset=$((512 * $offset_sectors))
      dd if=$out of=rw-fs bs=$offset skip=1
      mkfs.ext4 -L NIXOS_RW rw-fs
      debugfs -w rw-fs -f /dev/stdin <<EOF
        mkdir nix-store
        mkdir home
      EOF
      dd if=rw-fs of=$out conv=notrunc bs=$offset seek=1
    '';
  }
