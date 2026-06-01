# lian-li-linux — Nix packaging

A Nix flake that packages [`sgtaziz/lian-li-linux`](https://github.com/sgtaziz/lian-li-linux)
(open-source L-Connect 3 replacement: fan/RGB control + LCD streaming for Lian Li
devices) for NixOS, since upstream ships only Arch/Debian install steps.

Pinned to upstream commit `1e665a4` (v0.6.1). Built and verified against
nixos-26.05 (Rust 1.95).

## Status

Personal config, shared as-is. It packages someone else's app for my own machine
(a UNI FAN SL V2 on NixOS) and is published in case it saves you the same afternoon.

> **Note:** this flake was written largely with AI assistance (Claude) and runs on my own
> hardware — a UNI FAN SL V2, where the daemon detects the controller and drives the fan
> curve and RGB groups. It works for me, but it installs udev rules and runs a systemd
> user service, so give it a read before running it on yours.

- **Best-effort, no support guaranteed.** It may lag upstream; I bump it when I want a
  newer build.
- **PRs welcome** — including "it broke on a newer nixpkgs" fixes — but I make no promise
  to review promptly.
- MIT-licensed (the packaged app is also MIT), provided **without warranty**. You run it
  against your own hardware at your own risk.

## What's here

| Output | What it is |
| --- | --- |
| `packages.x86_64-linux.lianli-linux` | the daemon + Slint GUI + helper bins, udev rules, desktop entry |
| `packages.x86_64-linux.libevdi` | userspace-only libevdi (no kernel module), used as a link dep |
| `nixosModules.default` | `services.lianli.enable` — package + udev rules + per-user daemon |
| `homeManagerModules.default` | per-user package + daemon service (no udev — see note) |
| `overlays.default` | adds `lianli-linux` to a pkgs set |
| `devShells.x86_64-linux.default` | `nix develop` to `cargo build` from source by hand |

## Try it standalone

```bash
nix build .#lianli-linux
./result/bin/lianli-daemon --help
nix run .#lianli-linux       # launches the GUI (lianli-gui is mainProgram)
```

The daemon needs the udev rules installed (non-root USB access) and the kernel to
expose your device's hidraw node — so it only actually drives hardware once you
enable the NixOS module below and rebuild.

## Wire into your NixOS config

In your dotfiles `flake.nix` inputs:

```nix
lian-li-linux = {
  url = "github:SChimera/lian-li-linux-nix";
  inputs.nixpkgs.follows = "nixpkgs";   # build against your own nixpkgs, no extra one in the lock
};
```

Then add the module to your host's `modules = [ ... ]` list (inside `mkHost`,
where `inputs` is in scope):

```nix
inputs.lian-li-linux.nixosModules.default
{ services.lianli.enable = true; }
```

Rebuild, then start the user service (first time):

```bash
systemctl --user daemon-reload
systemctl --user enable --now lianli-daemon
```

`lianli-gui` is on your PATH and appears in your app launcher. Config lives at
`~/.config/lianli/config.json` (the GUI edits it via the daemon's IPC socket).

### Options

- `services.lianli.enable` — install package + udev rules + per-user daemon.
- `services.lianli.package` — override the package (defaults to building from this repo).
- `services.lianli.enableVirtualDisplay` — load the `evdi` kernel module for
  desktop-mode LCD devices (HydroShift II, Lancool 207 Digital, Universal Screen
  8.8"). **Leave `false` for the UNI FAN SL V2** — it's HID-only, no virtual display.

## Notes / known scope

- **UNI FAN SL V2** is HID fan + RGB only. The daemon links `libevdi` regardless
  (upstream's `lianli-evdi` crate always links it), which is why `libevdi.nix`
  exists — but the kernel module is never loaded for this hardware.
- **GUI runtime libs**: `lianli-gui` is wrapped to put Wayland/X11/GL/xkbcommon on
  `LD_LIBRARY_PATH` (Slint's winit backend dlopens them), so it should run under
  Wayland compositors like niri — though I drive it mostly through the daemon + config.
- **home-manager module** can't install system udev rules. If you use it instead of
  the NixOS module, add them at the system level too:
  `services.udev.packages = [ inputs.lian-li-linux.packages.x86_64-linux.lianli-linux ];`
  (or apply `overlays.default` and use `pkgs.lianli-linux`). Or just use the NixOS
  module (recommended).
- Helper binaries are included: `bind_tool` (pair wireless devices),
  `desktop-mode-probe`, `render-preview`.

## Updating to a newer upstream commit

1. Bump `rev` (and `version`) in `package.nix`.
2. Set `src.hash` to `lib.fakeHash`, build, paste the reported hash back.
3. If the slint pin changed in upstream's `Cargo.lock`, set `slintHash =
   lib.fakeHash`, rebuild, paste the new hash. Refresh the `outputHashes` key list
   if crate names/versions changed.
