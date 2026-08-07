{
  description = "lian-li-linux — open-source L-Connect 3 replacement (fan/RGB/LCD control for Lian Li devices), packaged for NixOS";

  # Pinned to nixos-26.05 to match the host system. Modules build against the
  # *consumer's* pkgs (see package option), so this input only affects the
  # standalone `nix build`/devShell here.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system} = {
        lianli-linux = pkgs.callPackage ./package.nix { };
        libevdi = pkgs.callPackage ./libevdi.nix { };
        default = self.packages.${system}.lianli-linux;
      };

      overlays.default = final: _prev: {
        lianli-linux = final.callPackage ./package.nix { };
      };

      nixosModules.default = import ./nixos-module.nix;
      homeManagerModules.default = import ./home-module.nix;

      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ self.packages.${system}.lianli-linux ];
        packages = with pkgs; [
          rust-analyzer
          clippy
          bun # frontend build (vite) + tauri dev
        ];
        # So `cargo run -p lianli-gui` from the shell can find the dlopen'd
        # tray-icon dependency.
        shellHook = ''
          export LD_LIBRARY_PATH=${
            pkgs.lib.makeLibraryPath (with pkgs; [ libayatana-appindicator ])
          }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        '';
      };
    };
}
