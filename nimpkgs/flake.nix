{
  description = "Nim Packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Add more packages here:
    checksums = {
      url = "github:nim-lang/checksums";
      flake = false;
    };

    db_connector = {
      url = "github:nim-lang/db_connector";
      flake = false;
    };

    nimja = {
      url = "github:enthus1ast/nimja";
      #rev = "master";
      flake = false;
    };

    dotenv = {
      url = "github:euantorano/dotenv.nim";
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
                mkdir -p $out/pkgs/
                # Detect if pkg is a folder or a single file
                if [ -d ${value}/src/${name} ]; then
                  # For folder
                  mkdir -p $out/pkgs/${name}
                  cp -r ${value}/src/${name}/* $out/pkgs/${name}
                else
                  # For single file
                  cp ${value}/src/${name}.nim $out/pkgs/${name}.nim
                fi
              '') (builtins.attrNames inputs));
        };
      });
}
