{
 inputs = {
	nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
	nvf.url = "github:NotAShelf/nvf";
 };

 outputs = { self, nixpkgs, nvf, ...}: {
	packages."x86_64-linux".default =
	 (nvf.lib.neovimConfiguration {
	 	pkgs = nixpkgs.legacyPackages."x86_64-linux";
		modules=[ ./nvf-configuration.nix];
	}).neovim;

	nixosConfiguration.nixos = nixpkgs.lib.nixosSystem {
		modules = [
		 ~/hao-nixos/modules/host/hao/configuration.nix
		 nvf.nixosModules.default
		];
	};
 };
}
