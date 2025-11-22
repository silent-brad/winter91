{
  description = "Nim Packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Add more packages here:
    happyx = {
      url = "github:nim-lang/db_connector";
      flake = false;
    };

    nimja = {
      url = "github:enthus1ast/nimja";
      #rev = "master";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "nim-pkgs";
          version = "0.0.1";
          src = ./.;

          configurePhase = ''
            mkdir -p $out/pkgs
          '';

          installPhase = builtins.concatStringsSep "\n" (builtins.map (name:
            if name == "self" || name == "nixpkgs" || name == "flake-utils" then
              ""
            else
              let value = inputs.${name};
              in ''
                mkdir -p $out/pkgs/${name}
                cp -r ${value}/src/${name}/* $out/pkgs/${name}
              '') (builtins.attrNames inputs));
        };

        devShells.default = pkgs.mkShell {
          shellHook = ''
            echo "Installing Nim Packages"
          '';
        };
      });
}
