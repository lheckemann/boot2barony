let 
pkgs = import <nixpkgs> {};
isoWritableModule = { config, pkgs, lib, ... }:
{
  config = {
    fileSystems."/nix/.rw-store" = lib.mkForce {
      fsType = "ext4";
      neededForBoot = true;
      device = "/dev/disk/by-label/NIXOS_RW";
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
    src = /var/empty;
    buildInputs = [ e2fsprogs utillinux ];
    buildPhase = ''
      dd if=/dev/zero of=store-rw bs=1M count=1024
      mkfs.ext4 store-rw -L NIXOS_RW
      cat ${config.system.build.isoImage}/iso/*.iso store-rw > $out
      sfdisk $out <<EOF
        type=L
      EOF
    '';
  }
