let pkgs = import <nixpkgs> {};
  bootConfig = { pkgs, lib, config, ... }: {
    sdImage.populateBootCommands = "";
  };
  evaluated = (import <nixpkgs/nixos/lib/eval-config.nix> {
    inherit (pkgs) system;
    modules = [
      ./barony-bootable.nix
      ./barony-config.nix
      <nixpkgs/nixos/modules/installer/cd-dvd/sd-image.nix>
      <nixpkgs/nixos/modules/profiles/installation-device.nix>
      bootConfig
    ];
  });
in
evaluated.config.system.build.sdImage.overrideAttrs (super: {
  ibl = evaluated.config.system.build.installBootLoader;
  buildCommand = ''
    ${super.buildCommand}

    set -x
    touch boot/device.map
    ${pkgs.grub}/sbin/grub-install --root-directory=boot $out
    set +x
  '';
})