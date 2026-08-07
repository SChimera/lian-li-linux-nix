# lian-li-linux: open-source Linux replacement for L-Connect 3.
# Builds the daemon (HID/USB device control) and the Tauri v2 + Vue GUI.
{
  lib,
  stdenvNoCC,
  rustPlatform,
  fetchFromGitHub,
  callPackage,
  pkg-config,
  cmake,
  nasm,
  makeWrapper,
  wrapGAppsHook3,
  coreutils,
  bun,
  # link/runtime libraries
  udev,
  libusb1,
  ffmpeg,
  fontconfig,
  freetype,
  libjpeg_turbo,
  libdrm,
  # tauri / webkit stack
  webkitgtk_4_1,
  gtk3,
  glib,
  libsoup_3,
  librsvg,
  libayatana-appindicator,
}:
let
  libevdi = callPackage ./libevdi.nix { };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "lian-li-linux";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "sgtaziz";
    repo = "lian-li-linux";
    tag = "v${finalAttrs.version}";
    fetchSubmodules = true; # vendored tinyuz + HDiffPatch C++ live in submodules
    hash = "sha256-/A57yb3S7iDz7MAsHTKDviayNvbPO+OVf0fWYMbOY+s=";
  };

  # Vue frontend dependencies, fetched by bun into node_modules as a
  # fixed-output derivation so the main build stays offline.
  bunDeps = stdenvNoCC.mkDerivation {
    pname = "lian-li-linux-bun-deps";
    inherit (finalAttrs) version src;
    nativeBuildInputs = [ bun ];
    buildPhase = ''
      runHook preBuild
      cd crates/lianli-gui
      export HOME=$TMPDIR
      export BUN_INSTALL_CACHE_DIR=$TMPDIR/bun-cache
      bun install --frozen-lockfile --no-progress --ignore-scripts
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R node_modules $out/
      runHook postInstall
    '';
    dontFixup = true;
    outputHashMode = "recursive";
    outputHash = "sha256-TXEu+SbVPdYhcg/9eFQlxwbCHpM1nyUEHqgSfNcazKg=";
  };

  cargoLock.lockFile = finalAttrs.src + "/Cargo.lock";

  nativeBuildInputs = [
    pkg-config
    cmake # turbojpeg-sys builds libjpeg-turbo via cmake
    nasm # ...which needs nasm for SIMD
    makeWrapper
    wrapGAppsHook3 # gsettings schemas etc. for the webkit GUI
    bun # runs the vite build for the Vue frontend
    rustPlatform.bindgenHook # ffmpeg-sys-next uses bindgen (sets LIBCLANG_PATH)
  ];

  # cmake is only a build tool for a -sys crate; there is no top-level
  # CMakeLists.txt, so don't let the cmake hook hijack the configure phase.
  dontUseCmakeConfigure = true;

  buildInputs = [
    udev # hidapi (hidraw backend) + device enumeration
    libusb1 # rusb
    ffmpeg # ffmpeg-next (libav*)
    fontconfig
    freetype
    libjpeg_turbo # turbojpeg
    libdrm
    libevdi # lianli-evdi links -levdi
    # Tauri v2 webview stack
    webkitgtk_4_1
    gtk3
    glib
    libsoup_3
    librsvg
  ];

  # Build the frontend dist/ ourselves from the prefetched node_modules, then
  # tell build.rs to skip its own bun-driven frontend build (which would try
  # the network).
  env.LIANLI_NO_FRONTEND = "1";

  preBuild = ''
    cp -R ${finalAttrs.bunDeps}/node_modules crates/lianli-gui/node_modules
    chmod -R u+w crates/lianli-gui/node_modules
    (
      cd crates/lianli-gui
      export HOME=$TMPDIR
      # Call vite's real entry point with bun directly: the node_modules/.bin
      # symlinks lose their relative-path context when copied out of bunDeps,
      # and their `#!/usr/bin/env node` shebangs wouldn't resolve here anyway.
      bun node_modules/vite/bin/vite.js build
    )
  '';

  # Tests touch real hardware / sockets; skip in the sandbox.
  doCheck = false;

  postPatch = ''
    # Upstream pins a rustup toolchain channel; nix supplies its own rustc and
    # ignores the file, but removing it avoids any confusion/warnings.
    rm -f rust-toolchain.toml
  '';

  postInstall = ''
    # udev rules — picked up by services.udev.packages = [ pkg ]
    install -Dm644 packaging/udev/99-lianli.rules \
      $out/lib/udev/rules.d/99-lianli.rules
    # NixOS validates absolute program paths in udev rules at build time, and
    # /bin/chmod doesn't exist here. Point the evdi rule at a real chmod.
    # (/bin/sh in the usbhid new_id rules is fine — it exists on NixOS.)
    substituteInPlace $out/lib/udev/rules.d/99-lianli.rules \
      --replace-fail "/bin/chmod" "${coreutils}/bin/chmod"

    # systemd user unit (for non-NixOS use; the NixOS/HM modules define their own)
    install -Dm644 packaging/systemd/lianli-daemon.service \
      $out/lib/systemd/user/lianli-daemon.service
    substituteInPlace $out/lib/systemd/user/lianli-daemon.service \
      --replace-fail /usr/bin/lianli-daemon $out/bin/lianli-daemon

    # desktop entry + icons
    install -Dm644 packaging/desktop/com.sgtaziz.lianlilinux.desktop \
      $out/share/applications/com.sgtaziz.lianlilinux.desktop
    install -Dm644 assets/icons/32x32.png \
      $out/share/icons/hicolor/32x32/apps/com.sgtaziz.lianlilinux.png
    install -Dm644 assets/icons/128x128.png \
      $out/share/icons/hicolor/128x128/apps/com.sgtaziz.lianlilinux.png
    install -Dm644 "assets/icons/128x128@2x.png" \
      $out/share/icons/hicolor/256x256/apps/com.sgtaziz.lianlilinux.png
    install -Dm644 assets/icons/icon.svg \
      $out/share/icons/hicolor/scalable/apps/com.sgtaziz.lianlilinux.svg
  '';

  # tray-icon dlopens libayatana-appindicator at runtime rather than linking it.
  postFixup = ''
    wrapProgram $out/bin/lianli-gui \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libayatana-appindicator ]}"
  '';

  passthru.libevdi = libevdi;

  meta = {
    description = "Open-source Linux replacement for L-Connect 3 — fan/RGB control and LCD streaming for Lian Li devices";
    homepage = "https://github.com/sgtaziz/lian-li-linux";
    license = lib.licenses.mit;
    mainProgram = "lianli-gui";
    platforms = [ "x86_64-linux" ];
  };
})
