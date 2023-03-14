{

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages = {
        inherit (pkgs.callPackage ./derivation.nix { }) mkPnpmPackage;
        example = pkgs.callPackage ./example self.packages.${system};
      };

      checks = {
        nixpkgs-fmt = pkgs.runCommand "check-nixpkgs-fmt" { nativeBuildInputs = [ pkgs.nixpkgs-fmt ]; } ''
          nixpkgs-fmt --check ${./.}
          touch $out
        '';

        build-example = self.packages.${system}.example;
      };
    });

}
