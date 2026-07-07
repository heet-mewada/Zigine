{
  description = "Zigine- 2D game engine";

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
    in
    {
      devShells.${system} = {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.zig
            pkgs.zig-zlint
            pkgs.zig-shell-completions
            pkgs.zig.hook

            pkgs.sdl3
            pkgs.libX11
            pkgs.libXi
            pkgs.libXcursor
            pkgs.libGL
            pkgs.alsa-lib

            pkgs.pkg-config
            pkgs.tree
            pkgs.onefetch

            pkgs.wayland
            pkgs.wayland-protocols
            pkgs.libxkbcommon
            pkgs.mesa
            pkgs.waypipe

            pkgs.neovim
            pkgs.zellij
          ];
          shellHook = ''
            exec zsh
          '';
        };

      };
    };
}
