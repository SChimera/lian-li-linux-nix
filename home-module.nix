# home-manager module for lian-li-linux.
#
# NOTE: home-manager cannot install system udev rules. The daemon needs the
# udev rules for non-root USB access, so EITHER also use the NixOS module
# (recommended), OR add the rules at system level yourself — referencing the
# package from this flake's output (or `overlays.default`):
#   services.udev.packages = [ inputs.lian-li-linux.packages.x86_64-linux.lianli-linux ];
#
# This module only installs the package and the per-user daemon service.
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
    enable = lib.mkEnableOption "the Lian Li device daemon (lian-li-linux), per-user";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The lian-li-linux package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.lianli-daemon = {
      Unit = {
        Description = "Lian Li Device Daemon";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${cfg.package}/bin/lianli-daemon";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
