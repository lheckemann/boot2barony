{ pkgs, lib, config, ... }:
let 
  baronyData = "${/home/linus/software/barony-data-only}";
in
{
  nixpkgs.config.allowUnfree = true;
  services.xserver = {
    enable = true;
    displayManager.auto = {
      enable = true;
      user = "barony";
    };
    desktopManager.xfce.enable = true;
    #windowManager.default = "barony";
    #windowManager.session = lib.singleton {
    #  name = "barony";
    #  start = ''
    #    ${pkgs.xfce.xfwm4}/bin/xfwm4 &
    #    waitPID=$!
    #    ${pkgs.xfce.xfce4panel}/bin/xfce4-panel &
    #    ${pkgs.networkmanagerapplet}/bin/nm-applet &
    #  '';
    #};
  };

  users.extraUsers.barony = {
    isNormalUser = true;
    uid = 1000;
  };

  environment.systemPackages = with pkgs; [];

  #system.activationScripts.baronyDesktop = let
  #  inherit (pkgs) stdenv writeText writeScriptBin barony;
  #  baronyScript = writeScriptBin "barony" ''
  #    #!${stdenv.shell}
  #    ${barony}/bin/barony "-datadir=${baronyData}"
  #  '';
  #  desktopFile = writeText "barony.desktop" ''
  #    [Desktop Entry]
  #    Version=1.0
  #    Type=Application
  #    Name=Barony
  #    Exec=${baronyScript}/bin/barony
  #    Icon=${baronyData}/Barony_Icon256x256.png
  #  '';
  #  in ''
  #    mkdir -p /home/barony/.local/share/applications
  #    ln -s ${desktopFile} /home/barony/.local/share/applications/barony.desktop
  #    mkdir -p /home/barony/Desktop
  #    ln -s ${desktopFile} /home/barony/Desktop/barony.desktop
  #    chown -R ${builtins.toString config.users.users.barony.uid} /home/barony
  #  '';

  hardware.enableAllFirmware = true;
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;
}
