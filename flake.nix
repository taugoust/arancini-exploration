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
        phoenixPackages = phoenix.packages.x86_64-linux;
        phoenixHistogramData = phoenix.packages.${system}.phoenix-input-data-histogram;
        phoenixData = phoenix.packages.${system}.phoenix-input-data;
        phoenix-seq = phoenixPackages.phoenix-x86_64-musl-static-seq;
        phoenix-pthread = phoenixPackages.phoenix-x86_64-musl-static-pthread;
        phoenix-mapreduce = phoenixPackages.phoenix-x86_64-musl-static-all;
        phoenix-musl-dynamic-seq = phoenixPackages.phoenix-x86_64-musl-dynamic-seq;
        phoenix-musl-dynamic-pthread = phoenixPackages.phoenix-x86_64-musl-dynamic-pthread;
        phoenix-glibc-dynamic-seq = phoenixPackages.phoenix-x86_64-glibc-dynamic-seq;
        phoenix-glibc-dynamic-pthread = phoenixPackages.phoenix-x86_64-glibc-dynamic-pthread;
        phoenix-glibc-static-pthread = phoenixPackages.phoenix-x86_64-glibc-static-pthread;
        mkPhoenixCheck =
          {
            name,
            cmakeFlags ? [ ],
            testRegex,
          }:
          let
            checkCmakeFlags =
              native_pkgs.lib.optionals (native_pkgs.lib.hasInfix "histogram" testRegex) [
                "-Dphoenix-data-root=${phoenixHistogramData}"
              ]
              ++ cmakeFlags;
          in
          native_pkgs.runCommand name
            {
              nativeBuildInputs = with native_pkgs; [
                cmake
                python3
                clang_18
                gcc
              ];
            }
            ''
              runHook preBuild

              mkdir -p test-src
              ln -s ${self.outPath}/aarch64.exec.lds test-src/aarch64.exec.lds
              ln -s ${self.outPath}/riscv64.exec.lds test-src/riscv64.exec.lds
              if [ -e ${self.outPath}/x86_64.exec.lds ]; then
                ln -s ${self.outPath}/x86_64.exec.lds test-src/x86_64.exec.lds
              fi
              ln -s ${self.outPath}/lib.lds test-src/lib.lds
              ln -s ${self.outPath}/lib.aarch64.lds test-src/lib.aarch64.lds
              cat > test-src/CMakeLists.txt <<EOF
cmake_minimum_required(VERSION 3.22)
project(arancini-test-wrapper LANGUAGES C CXX ASM)

add_executable(txlat IMPORTED GLOBAL)
set_target_properties(txlat PROPERTIES IMPORTED_LOCATION "${arancini-package}/bin/txlat")

add_library(arancini-runtime SHARED IMPORTED GLOBAL)
set_target_properties(arancini-runtime PROPERTIES IMPORTED_LOCATION "${arancini-package}/lib/libarancini-runtime.so")

enable_testing()
add_subdirectory("${self.outPath}/test" test)
EOF

              cmake -S test-src -B build \
                ${native_pkgs.lib.escapeShellArgs checkCmakeFlags}
              ctest --test-dir build --output-on-failure --no-tests=error \
                -R ${native_pkgs.lib.escapeShellArg testRegex}

              mkdir -p "$out"
              touch "$out/passed"

              runHook postBuild
            '';
      in
      {
        devShells =
          let
            commonArgs = {
              inputsFrom = [ arancini-package ];
              packages = [ arancini-package ] ++ (with native_pkgs; [
                binutils
                elfutils
                file
                gdb
                jq
                llvmPackages_18.llvm
                patchelf
                strace
              ]);
              ARANCINI_ROOT = "${arancini-package}";
            };
          in
          {
            default = native_pkgs.mkShell commonArgs;
            full = native_pkgs.mkShell (commonArgs // {
              packages = commonArgs.packages ++ [
                phoenix-mapreduce
                phoenixData
              ];
              PHOENIX_ROOT = "${phoenix-mapreduce}";
              PHOENIX_DATA_ROOT = "${phoenixData}";
            });
          };

        defaultPackage = arancini-package;
        checks =
          native_pkgs.lib.optionalAttrs (system == "aarch64-linux") {
          static-llvm-integer-division = native_pkgs.runCommand
            "arancini-static-llvm-integer-division"
            {
              nativeBuildInputs = with native_pkgs; [
                clang_18
                gcc
                llvmPackages_18.lld
              ];
            }
            ''
              cp ${self.outPath}/test/static-llvm-integer-division.S division.S
              clang --target=x86_64-unknown-linux-gnu -nostdlib -static \
                -fuse-ld=lld -Wl,--build-id=none,-e,_start \
                -o division.x86_64 division.S

              ln -s ${self.outPath}/aarch64.exec.lds
              ARANCINI_ENABLE_LOG=false ${arancini-package}/bin/txlat \
                --input division.x86_64 --output division.aarch64 \
                --cxx-compiler-path clang++ \
                --runtime-lib-path \
                  ${arancini-package}/lib/libarancini-runtime.so \
                --dump-llvm division

              grep -q " sdiv i64 " division.ll
              grep -q " udiv i64 " division.ll

              printf 'ok\n' > expected.stdout
              ARANCINI_ENABLE_LOG=false \
                LD_LIBRARY_PATH=${arancini-package}/lib \
                ./division.aarch64 > actual.stdout 2> actual.stderr
              cmp expected.stdout actual.stdout
              test ! -s actual.stderr

              mkdir -p "$out"
              touch "$out/passed"
            '';

          static-llvm-x87-extended-store = native_pkgs.runCommand
            "arancini-static-llvm-x87-extended-store"
            {
              nativeBuildInputs = with native_pkgs; [
                clang_18
                gcc
                llvmPackages_18.lld
              ];
            }
            ''
              cp ${self.outPath}/test/static-llvm-x87-extended-store.S x87-store.S
              clang --target=x86_64-unknown-linux-gnu -nostdlib -static \
                -fuse-ld=lld -Wl,--build-id=none,-e,_start \
                -o x87-store.x86_64 x87-store.S

              ln -s ${self.outPath}/aarch64.exec.lds
              ARANCINI_ENABLE_LOG=false ${arancini-package}/bin/txlat \
                --input x87-store.x86_64 --output x87-store.aarch64 \
                --cxx-compiler-path clang++ \
                --runtime-lib-path \
                  ${arancini-package}/lib/libarancini-runtime.so \
                --dump-llvm x87-store

              grep -q "store i80" x87-store.ll
              ! grep -q "i0" x87-store.ll

              printf 'ok\n' > expected.stdout
              ARANCINI_ENABLE_LOG=false \
                LD_LIBRARY_PATH=${arancini-package}/lib \
                ./x87-store.aarch64 > actual.stdout 2> actual.stderr
              cmp expected.stdout actual.stdout
              test ! -s actual.stderr

              mkdir -p "$out"
              touch "$out/passed"
            '';
          }
          # Reuse one system-parameterized Phoenix matrix for each native
          # backend instead of maintaining architecture-specific copies.
          // native_pkgs.lib.optionalAttrs
            (builtins.elem system [ "aarch64-linux" "riscv64-linux" ])
            {
          phoenix-histogram-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-histogram-seq-static-musl:dynamic$";
          };
          phoenix-histogram-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-histogram-seq-static-musl:hybrid$";
          };
          phoenix-histogram-pthread-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-pthread-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-histogram-pthread-static-musl:dynamic$";
          };
          phoenix-histogram-pthread-v2-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-histogram-pthread-v2-static-musl:dynamic$";
          };
          phoenix-histogram-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread}"
            ];
            testRegex = "^phoenix-histogram-pthread-static-glibc:dynamic$";
          };
          phoenix-kmeans-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread}"
            ];
            testRegex = "^phoenix-kmeans-pthread-static-glibc:dynamic$";
          };
          phoenix-linear-regression-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread}"
            ];
            testRegex = "^phoenix-linear-regression-pthread-static-glibc:dynamic$";
          };
          phoenix-matrix-multiply-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread}"
            ];
            testRegex = "^phoenix-matrix-multiply-pthread-static-glibc:dynamic$";
          };
          phoenix-pca-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread}"
            ];
            testRegex = "^phoenix-pca-pthread-static-glibc:dynamic$";
          };
          phoenix-string-match-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread}"
            ];
            testRegex = "^phoenix-string-match-pthread-static-glibc:dynamic$";
          };
          phoenix-word-count-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread}"
            ];
            testRegex = "^phoenix-word-count-pthread-static-glibc:dynamic$";
          };
          phoenix-histogram-pthread-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-pthread-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-glibc-pthread-phoenix-root=${phoenix-glibc-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-histogram-pthread-glibc:dynamic$";
          };
          phoenix-kmeans-pthread-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-pthread-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-glibc-pthread-phoenix-root=${phoenix-glibc-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-kmeans-pthread-glibc:dynamic$";
          };
          phoenix-linear-regression-pthread-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-pthread-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-glibc-pthread-phoenix-root=${phoenix-glibc-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-linear-regression-pthread-glibc:dynamic$";
          };
          phoenix-matrix-multiply-pthread-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-pthread-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-glibc-pthread-phoenix-root=${phoenix-glibc-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-matrix-multiply-pthread-glibc:dynamic$";
          };
          phoenix-pca-pthread-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-pthread-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-glibc-pthread-phoenix-root=${phoenix-glibc-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-pca-pthread-glibc:dynamic$";
          };
          phoenix-string-match-pthread-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-pthread-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-glibc-pthread-phoenix-root=${phoenix-glibc-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-string-match-pthread-glibc:dynamic$";
          };
          phoenix-word-count-pthread-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-pthread-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-glibc-pthread-phoenix-root=${phoenix-glibc-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-word-count-pthread-glibc:dynamic$";
          };
          phoenix-kmeans-pthread-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-pthread-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-kmeans-pthread-static-musl:dynamic$";
          };
          phoenix-kmeans-pthread-v2-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-kmeans-pthread-v2-static-musl:dynamic$";
          };
          phoenix-linear-regression-pthread-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-pthread-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-linear-regression-pthread-static-musl:dynamic$";
          };
          phoenix-linear-regression-pthread-v2-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-linear-regression-pthread-v2-static-musl:dynamic$";
          };
          phoenix-matrix-multiply-pthread-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-pthread-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-matrix-multiply-pthread-static-musl:dynamic$";
          };
          phoenix-matrix-multiply-pthread-v2-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-matrix-multiply-pthread-v2-static-musl:dynamic$";
          };
          phoenix-pca-pthread-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-pthread-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-pca-pthread-static-musl:dynamic$";
          };
          phoenix-pca-pthread-v2-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-pca-pthread-v2-static-musl:dynamic$";
          };
          phoenix-string-match-pthread-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-pthread-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-string-match-pthread-static-musl:dynamic$";
          };
          phoenix-string-match-pthread-v2-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-string-match-pthread-v2-static-musl:dynamic$";
          };
          phoenix-word-count-pthread-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-pthread-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-word-count-pthread-static-musl:dynamic$";
          };
          phoenix-word-count-pthread-v2-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-word-count-pthread-v2-static-musl:dynamic$";
          };
          phoenix-histogram-pthread-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-pthread-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-histogram-pthread-static-musl:hybrid$";
          };
          phoenix-histogram-pthread-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-pthread-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-histogram-pthread-v2-static-musl:hybrid$";
          };
          phoenix-kmeans-pthread-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-pthread-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-kmeans-pthread-static-musl:hybrid$";
          };
          phoenix-kmeans-pthread-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-pthread-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-kmeans-pthread-v2-static-musl:hybrid$";
          };
          phoenix-linear-regression-pthread-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-pthread-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-linear-regression-pthread-static-musl:hybrid$";
          };
          phoenix-linear-regression-pthread-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-pthread-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-linear-regression-pthread-v2-static-musl:hybrid$";
          };
          phoenix-matrix-multiply-pthread-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-pthread-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-matrix-multiply-pthread-static-musl:hybrid$";
          };
          phoenix-matrix-multiply-pthread-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-pthread-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-matrix-multiply-pthread-v2-static-musl:hybrid$";
          };
          phoenix-pca-pthread-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-pca-pthread-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-pca-pthread-static-musl:hybrid$";
          };
          phoenix-pca-pthread-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-pca-pthread-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-pca-pthread-v2-static-musl:hybrid$";
          };
          phoenix-string-match-pthread-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-pthread-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-string-match-pthread-static-musl:hybrid$";
          };
          phoenix-string-match-pthread-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-pthread-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-string-match-pthread-v2-static-musl:hybrid$";
          };
          phoenix-word-count-pthread-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-pthread-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-word-count-pthread-static-musl:hybrid$";
          };
          phoenix-word-count-pthread-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-pthread-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            testRegex = "^phoenix-word-count-pthread-v2-static-musl:hybrid$";
          };
          phoenix-histogram-mapreduce-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-mapreduce-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-histogram-mapreduce-static-musl:dynamic$";
          };
          phoenix-histogram-mapreduce-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-mapreduce-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-histogram-mapreduce-static-musl:hybrid$";
          };
          phoenix-histogram-mapreduce-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-mapreduce-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-histogram-mapreduce-v2-static-musl:hybrid$";
          };
          phoenix-kmeans-mapreduce-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-mapreduce-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-kmeans-mapreduce-static-musl:dynamic$";
          };
          phoenix-kmeans-mapreduce-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-mapreduce-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-kmeans-mapreduce-static-musl:hybrid$";
          };
          phoenix-kmeans-mapreduce-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-mapreduce-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-kmeans-mapreduce-v2-static-musl:hybrid$";
          };
          phoenix-linear-regression-mapreduce-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-mapreduce-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-linear-regression-mapreduce-static-musl:dynamic$";
          };
          phoenix-linear-regression-mapreduce-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-mapreduce-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-linear-regression-mapreduce-static-musl:hybrid$";
          };
          phoenix-linear-regression-mapreduce-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-mapreduce-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-linear-regression-mapreduce-v2-static-musl:hybrid$";
          };
          phoenix-matrix-multiply-mapreduce-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-mapreduce-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-matrix-multiply-mapreduce-static-musl:dynamic$";
          };
          phoenix-matrix-multiply-mapreduce-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-mapreduce-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-matrix-multiply-mapreduce-static-musl:hybrid$";
          };
          phoenix-matrix-multiply-mapreduce-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-mapreduce-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-matrix-multiply-mapreduce-v2-static-musl:hybrid$";
          };
          phoenix-pca-mapreduce-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-mapreduce-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-pca-mapreduce-static-musl:dynamic$";
          };
          phoenix-pca-mapreduce-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-pca-mapreduce-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-pca-mapreduce-static-musl:hybrid$";
          };
          phoenix-pca-mapreduce-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-pca-mapreduce-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-pca-mapreduce-v2-static-musl:hybrid$";
          };
          phoenix-string-match-mapreduce-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-mapreduce-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-string-match-mapreduce-static-musl:dynamic$";
          };
          phoenix-string-match-mapreduce-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-mapreduce-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-string-match-mapreduce-static-musl:hybrid$";
          };
          phoenix-string-match-mapreduce-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-mapreduce-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-string-match-mapreduce-v2-static-musl:hybrid$";
          };
          phoenix-word-count-mapreduce-static-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-mapreduce-static-musl-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-word-count-mapreduce-static-musl:dynamic$";
          };
          phoenix-word-count-mapreduce-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-mapreduce-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-word-count-mapreduce-static-musl:hybrid$";
          };
          phoenix-word-count-mapreduce-v2-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-mapreduce-v2-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-mapreduce-phoenix-root=${phoenix-mapreduce}"
            ];
            testRegex = "^phoenix-word-count-mapreduce-v2-static-musl:hybrid$";
          };
          phoenix-histogram-pthread-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-pthread-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-pthread-phoenix-root=${phoenix-musl-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-histogram-pthread-musl:dynamic$";
          };
          phoenix-kmeans-pthread-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-pthread-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-pthread-phoenix-root=${phoenix-musl-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-kmeans-pthread-musl:dynamic$";
          };
          phoenix-linear-regression-pthread-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-pthread-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-pthread-phoenix-root=${phoenix-musl-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-linear-regression-pthread-musl:dynamic$";
          };
          phoenix-matrix-multiply-pthread-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-pthread-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-pthread-phoenix-root=${phoenix-musl-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-matrix-multiply-pthread-musl:dynamic$";
          };
          phoenix-pca-pthread-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-pthread-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-pthread-phoenix-root=${phoenix-musl-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-pca-pthread-musl:dynamic$";
          };
          phoenix-string-match-pthread-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-pthread-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-pthread-phoenix-root=${phoenix-musl-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-string-match-pthread-musl:dynamic$";
          };
          phoenix-word-count-pthread-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-pthread-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-pthread-phoenix-root=${phoenix-musl-dynamic-pthread}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-word-count-pthread-musl:dynamic$";
          };
          phoenix-histogram-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-histogram-seq-musl:dynamic$";
          };
          phoenix-histogram-musl-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-musl-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-histogram-seq-musl:hybrid$";
          };
          phoenix-kmeans-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-kmeans-seq-musl:dynamic$";
          };
          phoenix-kmeans-musl-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-musl-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-kmeans-seq-musl:hybrid$";
          };
          phoenix-linear-regression-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-linear-regression-seq-musl:dynamic$";
          };
          phoenix-linear-regression-musl-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-musl-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-linear-regression-seq-musl:hybrid$";
          };
          phoenix-matrix-multiply-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-musl:dynamic$";
          };
          phoenix-matrix-multiply-musl-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-musl-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-musl:hybrid$";
          };
          phoenix-string-match-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-string-match-seq-musl:dynamic$";
          };
          phoenix-string-match-musl-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-musl-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-string-match-seq-musl:hybrid$";
          };
          phoenix-word-count-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-word-count-seq-musl:dynamic$";
          };
          phoenix-word-count-musl-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-musl-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-word-count-seq-musl:hybrid$";
          };
          phoenix-pca-musl-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-musl-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-pca-seq-musl:dynamic$";
          };
          phoenix-pca-musl-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-pca-musl-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-pca-seq-musl:hybrid$";
          };
          phoenix-histogram-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-histogram-seq-glibc:dynamic$";
          };
          phoenix-histogram-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-histogram-seq-glibc:hybrid$";
          };
          phoenix-kmeans-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-kmeans-seq-glibc:dynamic$";
          };
          phoenix-kmeans-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-kmeans-seq-glibc:hybrid$";
          };
          phoenix-linear-regression-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-linear-regression-seq-glibc:dynamic$";
          };
          phoenix-linear-regression-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-linear-regression-seq-glibc:hybrid$";
          };
          phoenix-matrix-multiply-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-glibc:dynamic$";
          };
          phoenix-matrix-multiply-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-glibc:hybrid$";
          };
          phoenix-pca-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-pca-seq-glibc:dynamic$";
          };
          phoenix-pca-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-pca-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-pca-seq-glibc:hybrid$";
          };
          phoenix-string-match-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-string-match-seq-glibc:dynamic$";
          };
          phoenix-string-match-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-string-match-seq-glibc:hybrid$";
          };
          phoenix-word-count-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-word-count-seq-glibc:dynamic$";
          };
          phoenix-word-count-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-word-count-seq-glibc:hybrid$";
          };
          phoenix-kmeans-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-kmeans-seq-static-musl:dynamic$";
          };
          phoenix-kmeans-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-kmeans-seq-static-musl:hybrid$";
          };
          phoenix-linear-regression-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-linear-regression-seq-static-musl:dynamic$";
          };
          phoenix-linear-regression-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-linear-regression-seq-static-musl:hybrid$";
          };
          phoenix-matrix-multiply-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-static-musl:dynamic$";
          };
          phoenix-matrix-multiply-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-static-musl:hybrid$";
          };
          phoenix-string-match-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-string-match-seq-static-musl:dynamic$";
          };
          phoenix-string-match-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-string-match-seq-static-musl:hybrid$";
          };
          phoenix-word-count-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-word-count-seq-static-musl:dynamic$";
          };
          phoenix-word-count-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-word-count-seq-static-musl:hybrid$";
          };
          phoenix-pca-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-pca-seq-static-musl:dynamic$";
          };
          phoenix-pca-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-pca-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            testRegex = "^phoenix-pca-seq-static-musl:hybrid$";
          };
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
