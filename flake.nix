{
  description = "Arancini dev shell";

  # To update flake.lock to the latest nixpkgs: `nix flake update`
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    phoenix = {
      url = "git+https://github.com/taugoust/phoenix.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    xed-src = {
      url = "github:intelxed/xed";
      flake = false;
    };
    mbuild-src = {
      url = "github:intelxed/mbuild";
      flake = false;
    };
    fadec-src = {
      url = "github:aengelke/fadec";
      flake = false;
    };
  };

  nixConfig.extra-substituters = [
    "https://cache.garnix.io"
    "https://tum-dse.cachix.org"
  ];
  nixConfig.extra-trusted-public-keys = [
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];

  # output format guide https://nixos.wiki/wiki/Flakes#Output_schema
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      phoenix,
      xed-src,
      mbuild-src,
      fadec-src,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "riscv64-linux" ] (
      system:
      let
        my-mbuild = native_pkgs.python3Packages.buildPythonPackage {
          pname = "mbuild";
          version = "2022.07.28";

          src = mbuild-src;
          patches = [ ./mbuild-riscv.patch ];
        };
        patched-xed = native_pkgs.callPackage (
          { stdenv, lib }:
          stdenv.mkDerivation {
            pname = "xed";
            version = "2022.08.11";

            src = xed-src;
            nativeBuildInputs = [ my-mbuild ];

            buildPhase = ''
              				    patchShebangs mfile.py

              					# this will build, test and install
              				    ./mfile.py --prefix $out'';

            dontInstall = true; # already installed during buildPhase
          }
        ) { };
        fadec = native_pkgs.callPackage (
          {
            stdenv,
            meson,
            ninja,
          }:
          stdenv.mkDerivation {
            name = "fadec";
            src = fadec-src;
            nativeBuildInputs = [
              meson
              ninja
            ];
          }
        ) { };
        native_pkgs = import nixpkgs { system = system; };
        arancini-package = native_pkgs.stdenv.mkDerivation {
          name = "arancini";
          pname = "txlat";
          src = self;
          nativeBuildInputs = with native_pkgs; [
            gdb
            python3
            cmake
            pkg-config
            gcc
            m4
            flex
            bison
            clang_18
          ];
          buildInputs =
            with native_pkgs;
            [
              fmt
              zlib
              boost
              patched-xed
              libffi
              fadec
              libxml2
              llvmPackages_18.llvm.dev
              llvmPackages_18.bintools
              llvmPackages_18.lld
              flex
            ]
            ++ native_pkgs.lib.optionals (system == "aarch64-linux") [ native_pkgs.keystone ];
          depsTargetTarget = [ native_pkgs.gcc ];
          configurePhase = ''
            					export FLAKE_BUILD=1
            					export NDEBUG=1
            					cmakeConfigurePhase
            				'';
          cmakeFlags = [ "-DBUILD_TESTS=1" ];
        };
        phoenix-seq = phoenix.packages.${system}.phoenix-x86_64-musl-static-seq;
        phoenix-linear-regression-seq-bin = phoenix-seq.overrideAttrs (_old: {
          installPhase = ''
            mkdir -p "$out/bin"
            install -m755 phoenix-2.0/tests/linear_regression/linear_regression-seq \
              "$out/bin/linear_regression-seq-static-musl"
          '';
        });
        phoenix-matrix-multiply-seq-bin = phoenix-seq.overrideAttrs (_old: {
          installPhase = ''
            mkdir -p "$out/bin"
            install -m755 phoenix-2.0/tests/matrix_multiply/matrix_multiply-seq \
              "$out/bin/matrix_multiply-seq-static-musl"
          '';
        });
        phoenix-string-match-seq-bin = phoenix-seq.overrideAttrs (_old: {
          installPhase = ''
            mkdir -p "$out/bin"
            install -m755 phoenix-2.0/tests/string_match/string_match-seq \
              "$out/bin/string_match-seq-static-musl"
          '';
        });
        phoenix-word-count-seq-bin = phoenix-seq.overrideAttrs (_old: {
          installPhase = ''
            mkdir -p "$out/bin"
            install -m755 phoenix-2.0/tests/word_count/word_count-seq \
              "$out/bin/word_count-seq-static-musl"
          '';
        });
      in
      {
        defaultPackage = arancini-package;
        checks = native_pkgs.lib.optionalAttrs (system == "aarch64-linux") {
          phoenix-histogram-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-histogram-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R phoenix-histogram-seq-static-musl
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-kmeans-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-kmeans-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R phoenix-kmeans-seq-static-musl
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-linear-regression-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-linear-regression-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-linear-regression-seq-bin}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R phoenix-linear-regression-seq-static-musl
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-matrix-multiply-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-matrix-multiply-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-matrix-multiply-seq-bin}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R phoenix-matrix-multiply-seq-static-musl
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-string-match-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-string-match-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-string-match-seq-bin}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R phoenix-string-match-seq-static-musl
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-word-count-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-word-count-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-word-count-seq-bin}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R phoenix-word-count-seq-static-musl
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-pca-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-pca-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R phoenix-pca-seq-static-musl
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
        };
      }
    )
    // flake-utils.lib.eachSystem [ "aarch64-linux" "riscv64-linux" ] (
      system:
      let
        my-mbuild = native_pkgs.python3Packages.buildPythonPackage {
          pname = "mbuild";
          version = "2022.07.28";

          src = mbuild-src;
          patches = [ ./mbuild-riscv.patch ];
        };
        patched-xed = native_pkgs.callPackage (
          { stdenv, lib }:
          stdenv.mkDerivation {
            pname = "xed";
            version = "2022.08.11";

            src = xed-src;
            nativeBuildInputs = [ my-mbuild ];

            buildPhase = ''
              					    patchShebangs mfile.py

              						# this will build, test and install
              					    ./mfile.py --prefix $out'';

            dontInstall = true; # already installed during buildPhase
          }
        ) { };
        fadec = native_pkgs.callPackage (
          {
            stdenv,
            meson,
            ninja,
          }:
          stdenv.mkDerivation {
            name = "fadec";
            src = fadec-src;
            nativeBuildInputs = [
              meson
              ninja
            ];
          }
        ) { };
        native_pkgs = import nixpkgs { system = "x86_64-linux"; };
        remote_pkgs = import nixpkgs {
          system = "x86_64-linux";
          crossSystem = system;
        };
      in
      {
        crossPackage = native_pkgs.stdenv.mkDerivation {
          name = "arancini";
          pname = "txlat";
          src = self;
          nativeBuildInputs = [
            native_pkgs.gdb
            native_pkgs.python3
            native_pkgs.cmake
            native_pkgs.pkg-config
            native_pkgs.m4
            native_pkgs.flex
            native_pkgs.bison
            native_pkgs.gcc
          ];
          buildInputs = [
            native_pkgs.fmt
            native_pkgs.zlib
            native_pkgs.boost
            patched-xed
            native_pkgs.libffi
            fadec
            native_pkgs.libxml2
            native_pkgs.llvmPackages_18.llvm.dev
            native_pkgs.llvmPackages_18.bintools
            native_pkgs.llvmPackages_18.lld
            native_pkgs.flex
          ] ++ native_pkgs.lib.optionals (system == "aarch64-linux") [ native_pkgs.keystone ];
          depsTargetTarget = [ remote_pkgs.gcc ];
          configurePhase = ''
            					export FLAKE_BUILD=1
            					export NDEBUG=1
            					cmakeConfigurePhase
            				'';
          cmakeFlags =
            [
              "-DBUILD_TESTS=1"
              "-DCMAKE_BUILD_TYPE=Release"
            ]
            ++ native_pkgs.lib.optionals (system == "riscv64-linux") [
              "-DDBT_ARCH=RISCV64"
            ]
            ++ native_pkgs.lib.optionals (system == "aarch64-linux") [
              "-DDBT_ARCH=AARCH64"
            ];
          fixupPhase = ''
            					ln -s ${remote_pkgs.gcc.outPath}/bin/g++ $out/cross-g++;
            				'';
        };
      }
    );
}
