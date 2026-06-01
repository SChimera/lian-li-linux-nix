# lian-li-linux: open-source Linux replacement for L-Connect 3.
# Builds the daemon (HID/USB device control) and the Slint GUI.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  callPackage,
  pkg-config,
  cmake,
  nasm,
  makeWrapper,
  coreutils,
  # link/runtime libraries
  udev,
  libusb1,
  ffmpeg,
  fontconfig,
  freetype,
  libjpeg_turbo,
  libdrm,
  wayland,
  libxkbcommon,
  libGL,
  libglvnd,
  libinput,
  libx11,
  libxcursor,
  libxrandr,
  libxi,
  libxcb,
}:
let
  libevdi = callPackage ./libevdi.nix { };

  # The Slint GUI uses the winit backend; its renderer dlopens GL/EGL and the
  # windowing libs at runtime rather than linking them, so they must be on
  # LD_LIBRARY_PATH for the wrapped binary.
  runtimeLibs = [
    libGL
    libglvnd
    wayland
    libxkbcommon
    fontconfig
    freetype
    libinput
    libx11
    libxcursor
    libxrandr
    libxi
    libxcb
  ];

  # All 17 git-sourced crates come from a single slint-ui/slint checkout, so
  # they share one source hash. Discover it via the fake-hash build once, then
  # paste the real value here.
  slintHash = "sha256-aVonGMjp2xKsLKR9MQN6gSvY3PpmZHb58GQaPmZ6EMU=";
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "lian-li-linux";
  version = "0.6.1-unstable-2026-05-30";

  src = fetchFromGitHub {
    owner = "sgtaziz";
    repo = "lian-li-linux";
    rev = "1e665a4df89fda6d66b1cf7f32aade3942e9ffc0";
    fetchSubmodules = true; # vendored tinyuz + HDiffPatch C++ live in submodules
    hash = "sha256-s0+RuFV0w7xKfM53oDGjg9hR5g9OfEBa35UikXIoc8U=";
  };

  cargoLock = {
    lockFile = finalAttrs.src + "/Cargo.lock";
    outputHashes = {
      "const-field-offset-0.2.0" = slintHash;
      "const-field-offset-macro-0.2.0" = slintHash;
      "i-slint-backend-linuxkms-1.16.0" = slintHash;
      "i-slint-backend-selector-1.16.0" = slintHash;
      "i-slint-backend-winit-1.16.0" = slintHash;
      "i-slint-common-1.16.0" = slintHash;
      "i-slint-compiler-1.16.0" = slintHash;
      "i-slint-core-1.16.0" = slintHash;
      "i-slint-core-macros-1.16.0" = slintHash;
      "i-slint-renderer-femtovg-1.16.0" = slintHash;
      "i-slint-renderer-skia-1.16.0" = slintHash;
      "i-slint-renderer-software-1.16.0" = slintHash;
      "slint-1.16.0" = slintHash;
      "slint-build-1.16.0" = slintHash;
      "slint-macros-1.16.0" = slintHash;
      "vtable-0.4.0" = slintHash;
      "vtable-macro-0.4.0" = slintHash;
    };
  };

  nativeBuildInputs = [
    pkg-config
    cmake # turbojpeg-sys builds libjpeg-turbo via cmake
    nasm # ...which needs nasm for SIMD
    makeWrapper
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
  ] ++ runtimeLibs;

  env.SLINT_NO_QT = "1";

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
    install -Dm644 assets/icons/icon.svg \
      $out/share/icons/hicolor/scalable/apps/com.sgtaziz.lianlilinux.svg
  '';

  postFixup = ''
    wrapProgram $out/bin/lianli-gui \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
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
