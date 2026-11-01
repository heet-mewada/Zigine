

{
  description = "Zigine - 2D game engine";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      lib = pkgs.lib;

      runtimeLibs = with pkgs; [
        sdl3
        wayland
        wayland-protocols
        libxkbcommon
        libdecor
        libGL
        mesa
        stdenv.cc.cc.lib
        libx11
        libxext
        libxcursor
        libxi
        libxrandr
        libxfixes
        libxcb
        alsa-lib
        udev
      ];

      sdl3Binding = pkgs.fetchgit {
        url = "https://codeberg.org/7Games/zig-sdl3";
        rev = "83c694024f23cbacfa36fcd8fca1c57d4957203e";
        hash = "sha256-0mHREylA0VJ/w4VIUNg4umpTGpE7DBJg1pyYHuzY8OE=";
      };

      desktopItem = pkgs.makeDesktopItem {
        name = "zigine";
        desktopName = "Zigine";
        comment = "Zigine 2D game engine";
        exec = "zigine";
        terminal = false;
        categories = [ "Development" "Game" ];
      };

      zigine = pkgs.stdenv.mkDerivation {
        pname = "zigine";
        version = "0.1.0";

        src = self;

        nativeBuildInputs = with pkgs; [
          zig
          pkg-config
          makeWrapper
        ];

        buildInputs = runtimeLibs;

        postPatch = ''
          mkdir -p build-deps
          cp -r ${sdl3Binding} build-deps/zig-sdl3
          chmod -R u+w build-deps

          # Use the pinned SDL3 Zig binding locally.
          substituteInPlace build.zig.zon \
            --replace-fail \
              'url = "git+https://codeberg.org/7Games/zig-sdl3?ref=v0.2.2#83c694024f23cbacfa36fcd8fca1c57d4957203e",' \
              'path = "build-deps/zig-sdl3",' \
            --replace-fail \
              '.hash = "sdl3-0.2.2-NmT1Q-2jKQBa4uSXUwuVwdmXpXe-eYwim7Wkyx531v6O",' \
              ""

          # TTF is only used by the separate SDL test program.
          # Disable it in this packaged build, not in the project source.
          substituteInPlace build.zig \
            --replace-fail '.ext_ttf = true,' '.ext_ttf = false,'

          # These dependencies are not needed when TTF is disabled.
          sed -i '/\.freetype = \.{/,/^[[:space:]]*},/ {
            /^[[:space:]]*},/i\
                    .lazy = true,
          }' build-deps/zig-sdl3/build.zig.zon

          sed -i '/\.harfbuzz = \.{/,/^[[:space:]]*},/ {
            /^[[:space:]]*},/i\
                    .lazy = true,
          }' build-deps/zig-sdl3/build.zig.zon
        '';

        buildPhase = ''
          runHook preBuild
          zig build -Doptimize=ReleaseFast -fsys=sdl
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          install -Dm755 zig-out/bin/zigine "$out/bin/zigine"

          mkdir -p "$out/share/applications"
          cp ${desktopItem}/share/applications/zigine.desktop \
            "$out/share/applications/zigine.desktop"

          wrapProgram "$out/bin/zigine" \
            --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"

          runHook postInstall
        '';

        meta = {
          description = "Zigine 2D game engine";
          platforms = [ "x86_64-linux" ];
          mainProgram = "zigine";
        };
      };

    in {
      packages.${system} = {
        default = zigine;
        zigine = zigine;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${zigine}/bin/zigine";
        };

        zigine = {
          type = "app";
          program = "${zigine}/bin/zigine";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          zig
          zig-zlint
          zig-shell-completions
          zig.hook
          sdl3

          libx11
          libxi
          libxcursor
          libGL
          alsa-lib

          pkg-config
          tree
          onefetch

          wayland
          wayland-protocols
          libxkbcommon
          libdecor
          mesa
          waypipe

          libxext
          libxrandr
          libxfixes
          libxcb
          udev

          neovim
          zellij
          jetbrains-mono
        ];

        LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;

        shellHook = ''
          if [ -z "''${ZIGINE_LAUNCHER:-}" ]; then
            onefetch
            exec zsh
          fi
        '';
      };
    };
}

