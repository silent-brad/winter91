{
  description = "Winter 100 Challenge";

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

          buildInputs = with pkgs; [ nim-2_0 sqlite ];

          buildPhase = ''
            mkdir -p $out/bin

            # Manually install nim packages
            for pkg in ${nim-pkgs.packages.${system}.default}/pkgs/*; do
              # Detect if pkg is a folder or a single file
              if [ -d $pkg ]; then
                cp -r $pkg src/$(basename $pkg)
              else
                cp $pkg src/
              fi
            done

            export HOME=$(pwd)
            cd src && ${pkgs.nim-2_0}/bin/nim c -d:release --mm:none -o:$out/bin/app main.nim
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ nim-2_0 sqlite ];
          shellHook = ''
            echo "Nimrod: $(${pkgs.nim-2_0}/bin/nim -v)"
            echo "Run './result/bin/app'."
          '';
        };
      });
}
