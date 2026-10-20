{
  description = "Zigine - 2D game engine";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      runtimeLibs = with pkgs; [
        sdl3
        wayland
        libxkbcommon
        libdecor
        libGL
        mesa
        stdenv.cc.cc.lib

        xorg.libX11
        xorg.libXext
        xorg.libXcursor
        xorg.libXi
        xorg.libXrandr
        xorg.libXfixes
        xorg.libxcb

        alsa-lib
        udev
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          zig
          zig-zlint
          zig-shell-completions
          zig.hook

          sdl3

          libX11
          libXi
          libXcursor
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

          xorg.libXext
          xorg.libXrandr
          xorg.libXfixes
          xorg.libxcb

          udev

          neovim
          zellij

          jetbrains-mono
        ];

        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs;

        shellHook = ''
          onefetch
          exec zsh
        '';
      };
    };
}
