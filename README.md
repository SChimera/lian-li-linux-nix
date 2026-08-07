# lian-li-linux — Nix packaging

A Nix flake that packages [`sgtaziz/lian-li-linux`](https://github.com/sgtaziz/lian-li-linux)
(open-source L-Connect 3 replacement: fan/RGB control + LCD streaming for Lian Li
devices) for NixOS. Built for my own use because upstream ships only Arch/Debian
install steps with no Nix packaging.

Pinned to upstream `v0.8.0`. Built and verified against nixos-26.05.

## Status

Personal config, shared as-is. It packages someone else's app for my own machine
(a UNI FAN SL V2 on NixOS), published in case it saves you the same afternoon.

> **Note:** this flake was written largely with AI assistance (Claude). On my hardware
> the daemon detects the controller and drives the fan curve and RGB groups — but it
> installs udev rules and runs a systemd user service, so give it a read before running
> it on yours.

- **Best-effort, no support guaranteed.** It may lag upstream; I bump it when I want a
  newer build.
- **PRs welcome** — including "it broke on a newer nixpkgs" fixes — but I make no promise
  to review promptly.
- MIT-licensed (the packaged app is also MIT), provided **without warranty**. You run it
  against your own hardware at your own risk.

## What's here

| Output | What it is |
| --- | --- |
| `packages.x86_64-linux.lianli-linux` | the daemon + Tauri/Vue GUI + helper bins, udev rules, desktop entry |
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

## Notes / scope

This packages the **whole** upstream app (fan/RGB, wireless devices, and LCD/virtual-display
devices). A few things hold regardless of which device you have:

- **`libevdi` is always a build dependency.** Upstream's `lianli-evdi` crate links
  `libevdi.so` unconditionally, so the daemon won't compile without it — hence `libevdi.nix`
  (a userspace-only build of it). The evdi **kernel module** is a separate, runtime-only
  concern: off by default, needed only for desktop-mode LCD devices (HydroShift II, Lancool
  207 Digital, Universal Screen 8.8"). Turn it on with `services.lianli.enableVirtualDisplay = true`.
- **The GUI is a Tauri v2 + Vue app** (upstream switched from Slint in 0.7/0.8). The Vue
  frontend is built at package time by a fixed-output `bunDeps` derivation (`bun install`)
  plus a `vite build` in `preBuild`, so the main build stays offline. The webview stack
  (webkitgtk 4.1, gtk3, libsoup 3) is linked normally; only the tray icon's
  `libayatana-appindicator` is `dlopen`ed, so the binary is wrapped for just that.
- **home-manager can't install system udev rules** (they're system-level). Use the NixOS
  module, which does both, or add `services.udev.packages` yourself (see the home-manager
  module's note).
- **Helper binaries ship** alongside the daemon and GUI: `bind_tool` (pair wireless
  devices), `desktop-mode-probe` (diagnose LCD/desktop-mode devices), `render-preview`
  (preview LCD media).

**Tested scope:** I only have a **UNI FAN SL V2** (HID fan + RGB), so that's all I've
actually verified. The wireless and LCD/virtual-display paths are built but **untested by
me** — reports/PRs welcome.

## Updating to a newer upstream commit

1. Bump `version` (the `src` tag follows it) in `package.nix`.
2. Set `src.hash` to `lib.fakeHash`, build, paste the reported hash back.
3. If `bun.lock` changed upstream, set `bunDeps.outputHash` to `lib.fakeHash`,
   rebuild, paste the new hash.
