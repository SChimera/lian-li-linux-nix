# NixOS module for lian-li-linux.
#
# Enable with:  services.lianli.enable = true;
# This installs the package, the udev rules (non-root USB access), and runs the
# daemon as a per-user systemd service. The GUI is on PATH as `lianli-gui`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.lianli;
in
{
  options.services.lianli = {
    enable = lib.mkEnableOption "the Lian Li device daemon (lian-li-linux)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The lian-li-linux package to use.";
    };

    enableVirtualDisplay = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Load the evdi kernel module so desktop-mode LCD devices (HydroShift II,
        Lancool 207 Digital, Universal Screen 8.8") are attached as virtual
        displays. Not needed for HID-only devices like the UNI FAN SL V2.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Grants the active user non-root access to the device hidraw/usb nodes.
    services.udev.packages = [ cfg.package ];

    # The daemon is designed to run per-user (talks to the GUI over a socket in
    # $XDG_RUNTIME_DIR), so it's a systemd *user* service.
    systemd.user.services.lianli-daemon = {
      description = "Lian Li Device Daemon";
      wantedBy = [ "default.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/lianli-daemon";
        Restart = "on-failure";
        RestartSec = 5;
        # Shell-command and NvidiaGpu fan-curve sensor sources run via
        # `Command::new("sh")` and call out to nvidia-smi / awk etc. The default
        # systemd user PATH is coreutils-only (no `sh`!), so point the daemon at
        # the system profile for those sensor sources to work.
        Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin";
      };
    };

    boot.extraModulePackages = lib.mkIf cfg.enableVirtualDisplay [
      config.boot.kernelPackages.evdi
    ];
    boot.kernelModules = lib.mkIf cfg.enableVirtualDisplay [ "evdi" ];
  };
}
