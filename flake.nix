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

          buildInputs = with pkgs; [ nim-2_0 ];

          buildPhase = ''
            mkdir -p $out/bin
            mkdir -p $out

            # Manually install nim packages
            for pkg in ${nim-pkgs.packages.${system}.default}/pkgs/*; do
              cp -r $pkg src/$(basename $pkg)
            done

            # Copy templates to output directory for runtime
            cp -r templates $out/

            export HOME=$(pwd)
            ${pkgs.nim-2_0}/bin/nim c -d:release -o:$out/bin/app src/main.nim
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ nim-2_0 ];
          shellHook = ''
            echo "Nimrod: $(${pkgs.nim-2_0}/bin/nim -v)"
            echo "Run './result/bin/app'."
          '';
        };
      });
}
