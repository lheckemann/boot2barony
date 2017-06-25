let
  pkgs = import <nixpkgs> {};
  config = {...}: {
    imports = [
      #./barony-config.nix
      <nixpkgs/nixos/modules/hardware/all-firmware.nix>
      <nixpkgs/nixos/modules/profiles/all-hardware.nix>
      <nixpkgs/nixos/modules/profiles/base.nix>
    ];
    fileSystems."/" = { device = "LABEL=nixos"; fsType = "ext4"; };
    boot.loader.grub.devices = [ "/dev/vda" ];
  };
  evaluated = (import <nixpkgs/nixos/lib/eval-config.nix> {
    inherit (pkgs) system;
    modules = [ config ];
  });
  image = import ./make-disk-image.nix {
    name = "superMagicWritableUSB";
    inherit pkgs;
    inherit (pkgs) lib;
    config = (import <nixpkgs/nixos> { configuration = config; }).config;
    installBootLoader = true;
    diskSize = 3072;
  };
in
  image
