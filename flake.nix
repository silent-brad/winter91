{
  description = "Winter91 Challenge";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nim-pkgs.url = "path:./nimpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, nim-pkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "winter-100";
          version = "0.0.1";
          src = ./.;

          buildInputs = with pkgs; [ nim-2_0 sqlite openssl imagemagick ];

          buildPhase = ''
            mkdir -p $out/bin

            # Setup nim package path
            export HOME=$(pwd)
            export PATH=$PATH:${pkgs.imagemagick}/bin
            mkdir -p packages

            for pkg in ${nim-pkgs.packages.${system}.default}/pkgs/*; do
              # Copy package to local packages directory
              if [ -d $pkg ]; then
                cp -r $pkg packages/
              else
                cp $pkg packages/
              fi
            done

            ${pkgs.nim-2_0}/bin/nim c -d:release -d:ssl --mm:none --path:../packages -o:$out/bin/app src/main.nim
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ nim-2_0 sqlite openssl ];
          shellHook = ''
            echo "Nimrod: $(${pkgs.nim-2_0}/bin/nim -v)"
            echo "Run './result/bin/app'."
          '';
        };
      });
}
