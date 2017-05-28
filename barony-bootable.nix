{ pkgs, config, lib, ... }:
{
  boot.loader.grub.enable = lib.mkForce true;
  boot.loader.grub.device = "nodev";

}
