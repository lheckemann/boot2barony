let
  pkgs = import <nixpkgs> {};
  config = {...}: {
    imports = [
      ./barony-config.nix
      <nixpkgs/nixos/modules/hardware/all-firmware.nix>
      <nixpkgs/nixos/modules/profiles/all-hardware.nix>
      <nixpkgs/nixos/modules/profiles/base.nix>
    ];
    environment.systemPackages = [ pkgs.nix ];
    fileSystems."/" = { device = "LABEL=NIXOS_IMG_ROOT"; fsType = "ext4"; };
    boot.loader.grub.enable = false;
    boot.loader.systemd-boot.enable = true;
    #boot.loader.grub.devices = [ "/dev/vda" ];
    i18n.supportedLocales = ["en_US.UTF-8/UTF-8"];
    boot.kernelParams = ["boot.shell_on_fail" "loglevel=7"];
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
    diskSize = 4096;
  };
in
  image // {
    inherit (evaluated) config;
  }
