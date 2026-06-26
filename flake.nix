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
        phoenix-pthread = phoenix.packages.${system}.phoenix-x86_64-musl-static-pthread;
        phoenix-musl-dynamic-seq-bin = phoenix-seq.overrideAttrs (_old: {
          name = "phoenix-x86_64-musl-dynamic-seq";
          dontPatchELF = true;
          dontFixup = true;
          hardeningDisable = [ "pie" "stackprotector" ];
          buildPhase = ''
            runHook preBuild
            cflags="-D_LINUX_ -D__x86_64__ -D_GNU_SOURCE -Wall -O2 -g -mno-avx -mno-avx2 -fno-tree-vectorize -fno-stack-protector -no-pie"
            cc="x86_64-unknown-linux-musl-gcc"
            ar="x86_64-unknown-linux-musl-ar"
            ranlib="x86_64-unknown-linux-musl-ranlib"
            make -C phoenix-2.0/src CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            for app in histogram kmeans linear_regression matrix_multiply pca string_match word_count; do
              make -C "phoenix-2.0/tests/$app" "$app-seq" \
                CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            done
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin" "$out/data"
            for app in histogram kmeans linear_regression matrix_multiply pca string_match word_count; do
              install -m755 "phoenix-2.0/tests/$app/$app-seq" "$out/bin/$app-seq-v2"
              cp -p "$out/bin/$app-seq-v2" "$out/bin/$app-seq"
            done
            cp -a ${phoenix-seq}/data/. "$out/data/"
            runHook postInstall
          '';
        });
        phoenix-musl-dynamic-seq =
          phoenix.packages.${system}.phoenix-x86_64-musl-dynamic-seq
            or phoenix-musl-dynamic-seq-bin;
        glibc-x86_64-pkgs = native_pkgs.pkgsCross.gnu64;
        phoenix-glibc-dynamic-seq-bin = glibc-x86_64-pkgs.stdenv.mkDerivation {
          pname = "phoenix-x86_64-glibc-dynamic-seq";
          version = "2.0";
          src = phoenix.outPath;
          nativeBuildInputs = with native_pkgs; [ gnumake gnused coreutils ];
          dontConfigure = true;
          dontStrip = true;
          dontPatchELF = true;
          dontFixup = true;
          hardeningDisable = [ "all" ];
          postPatch = ''
            find phoenix-2.0 sample_apps -type f \( -name '*.c' -o -name '*.h' \) \
              -exec sed -i 's@#include <sys/unistd.h>@#include <unistd.h>@' {} +
            substituteInPlace phoenix-2.0/tests/histogram/histogram-seq.c \
              --replace-fail '   return 0;' '   exit(0);'
            substituteInPlace phoenix-2.0/tests/kmeans/kmeans-seq.c \
              --replace-fail '    return 0;  ' '    exit(0);'
            substituteInPlace phoenix-2.0/tests/linear_regression/linear_regression-seq.c \
              --replace-fail '   return 0;' '   exit(0);'
            substituteInPlace phoenix-2.0/tests/matrix_multiply/matrix_multiply-seq.c \
              --replace-fail '   return 0;' '   exit(0);'
            substituteInPlace phoenix-2.0/tests/pca/pca-seq.c \
              --replace-fail '   return 0;' '   exit(0);'
            substituteInPlace phoenix-2.0/tests/string_match/string_match-seq.c \
              --replace-fail '   return 0;' '   exit(0);'
            substituteInPlace phoenix-2.0/tests/word_count/word_count-seq.c \
              --replace-fail '   return 0;' '   exit(0);'
          '';
          buildPhase = ''
            runHook preBuild
            cflags="-D_LINUX_ -D__x86_64__ -D_GNU_SOURCE -Wall -O2 -g -mno-avx -mno-avx2 -fno-tree-vectorize -fno-stack-protector -fno-PIE"
            cc="${glibc-x86_64-pkgs.stdenv.cc.targetPrefix}gcc -no-pie"
            ar="${glibc-x86_64-pkgs.stdenv.cc.targetPrefix}ar"
            ranlib="${glibc-x86_64-pkgs.stdenv.cc.targetPrefix}ranlib"
            make -C phoenix-2.0/src CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/histogram histogram-seq \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/kmeans kmeans-seq \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/linear_regression linear_regression-seq \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/matrix_multiply matrix_multiply-seq \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/pca pca-seq \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/string_match string_match-seq \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/word_count word_count-seq \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin"
            install -m755 phoenix-2.0/tests/histogram/histogram-seq "$out/bin/histogram-seq-v2"
            cp -p "$out/bin/histogram-seq-v2" "$out/bin/histogram-seq"
            install -m755 phoenix-2.0/tests/kmeans/kmeans-seq "$out/bin/kmeans-seq-v2"
            cp -p "$out/bin/kmeans-seq-v2" "$out/bin/kmeans-seq"
            install -m755 phoenix-2.0/tests/linear_regression/linear_regression-seq "$out/bin/linear_regression-seq-v2"
            cp -p "$out/bin/linear_regression-seq-v2" "$out/bin/linear_regression-seq"
            install -m755 phoenix-2.0/tests/matrix_multiply/matrix_multiply-seq "$out/bin/matrix_multiply-seq-v2"
            cp -p "$out/bin/matrix_multiply-seq-v2" "$out/bin/matrix_multiply-seq"
            install -m755 phoenix-2.0/tests/pca/pca-seq "$out/bin/pca-seq-v2"
            cp -p "$out/bin/pca-seq-v2" "$out/bin/pca-seq"
            install -m755 phoenix-2.0/tests/string_match/string_match-seq "$out/bin/string_match-seq-v2"
            cp -p "$out/bin/string_match-seq-v2" "$out/bin/string_match-seq"
            install -m755 phoenix-2.0/tests/word_count/word_count-seq "$out/bin/word_count-seq-v2"
            cp -p "$out/bin/word_count-seq-v2" "$out/bin/word_count-seq"
            runHook postInstall
          '';
        };
        phoenix-glibc-dynamic-seq =
          phoenix.packages.${system}.phoenix-x86_64-glibc-dynamic-seq or null;
        phoenix-glibc-dynamic-histogram-seq =
          phoenix.packages.${system}.phoenix-x86_64-glibc-dynamic-seq
            or phoenix-glibc-dynamic-seq-bin;
        phoenix-glibc-dynamic-kmeans-seq =
          phoenix.packages.${system}.phoenix-x86_64-glibc-dynamic-seq
            or phoenix-glibc-dynamic-seq-bin;
        phoenix-glibc-dynamic-linear-regression-seq =
          phoenix.packages.${system}.phoenix-x86_64-glibc-dynamic-seq
            or phoenix-glibc-dynamic-seq-bin;
        phoenix-glibc-dynamic-matrix-multiply-seq =
          phoenix.packages.${system}.phoenix-x86_64-glibc-dynamic-seq
            or phoenix-glibc-dynamic-seq-bin;
        phoenix-glibc-dynamic-pca-seq =
          phoenix.packages.${system}.phoenix-x86_64-glibc-dynamic-seq
            or phoenix-glibc-dynamic-seq-bin;
        phoenix-glibc-dynamic-string-match-seq =
          phoenix.packages.${system}.phoenix-x86_64-glibc-dynamic-seq
            or phoenix-glibc-dynamic-seq-bin;
        phoenix-glibc-dynamic-word-count-seq =
          phoenix.packages.${system}.phoenix-x86_64-glibc-dynamic-seq
            or phoenix-glibc-dynamic-seq-bin;
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
              ctest --output-on-failure -R '^phoenix-histogram-seq-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-histogram-static-musl-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-histogram-static-musl-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-histogram-seq-static-musl:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-histogram-pthread-static-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-histogram-pthread-static-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-histogram-pthread-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-histogram-pthread-v2-static-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-histogram-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-histogram-pthread-v2-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-kmeans-pthread-static-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-kmeans-pthread-static-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-kmeans-pthread-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-kmeans-pthread-v2-static-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-kmeans-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-kmeans-pthread-v2-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-linear-regression-pthread-static-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-linear-regression-pthread-static-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-linear-regression-pthread-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-linear-regression-pthread-v2-static-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-linear-regression-pthread-v2-static-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-pthread-phoenix-root=${phoenix-pthread}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-linear-regression-pthread-v2-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-histogram-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-histogram-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-histogram-seq-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-histogram-musl-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-histogram-musl-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-histogram-seq-musl:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-kmeans-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-kmeans-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-kmeans-seq-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-kmeans-musl-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-kmeans-musl-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-kmeans-seq-musl:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-linear-regression-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-linear-regression-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-linear-regression-seq-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-linear-regression-musl-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-linear-regression-musl-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-linear-regression-seq-musl:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-matrix-multiply-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-matrix-multiply-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-matrix-multiply-seq-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-matrix-multiply-musl-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-matrix-multiply-musl-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-matrix-multiply-seq-musl:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-string-match-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-string-match-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-string-match-seq-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-string-match-musl-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-string-match-musl-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-string-match-seq-musl:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-word-count-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-word-count-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-word-count-seq-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-word-count-musl-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-word-count-musl-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-word-count-seq-musl:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-pca-musl-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-pca-musl-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-pca-seq-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-pca-musl-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-pca-musl-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-musl-phoenix-root=${phoenix-musl-dynamic-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-pca-seq-musl:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-histogram-glibc-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-histogram-glibc-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-histogram-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-histogram-seq-glibc:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-histogram-glibc-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-histogram-glibc-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-histogram-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-histogram-seq-glibc:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-kmeans-glibc-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-kmeans-glibc-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-kmeans-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-kmeans-seq-glibc:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-kmeans-glibc-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-kmeans-glibc-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-kmeans-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-kmeans-seq-glibc:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-linear-regression-glibc-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-linear-regression-glibc-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-linear-regression-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-linear-regression-seq-glibc:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-linear-regression-glibc-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-linear-regression-glibc-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-linear-regression-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-linear-regression-seq-glibc:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-matrix-multiply-glibc-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-matrix-multiply-glibc-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-matrix-multiply-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-matrix-multiply-seq-glibc:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-matrix-multiply-glibc-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-matrix-multiply-glibc-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-matrix-multiply-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-matrix-multiply-seq-glibc:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-pca-glibc-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-pca-glibc-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-pca-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-pca-seq-glibc:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-pca-glibc-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-pca-glibc-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-pca-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-pca-seq-glibc:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-string-match-glibc-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-string-match-glibc-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-string-match-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-string-match-seq-glibc:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-string-match-glibc-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-string-match-glibc-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-string-match-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-string-match-seq-glibc:hybrid$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-word-count-glibc-dynamic-no-static = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-word-count-glibc-dynamic-no-static";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-word-count-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-word-count-seq-glibc:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-word-count-glibc-dynamic-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-word-count-glibc-dynamic-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-word-count-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-word-count-seq-glibc:hybrid$'
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
              ctest --output-on-failure -R '^phoenix-kmeans-seq-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-kmeans-static-musl-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-kmeans-static-musl-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-kmeans-seq-static-musl:hybrid$'
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
              ctest --output-on-failure -R '^phoenix-linear-regression-seq-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-linear-regression-static-musl-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-linear-regression-static-musl-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-linear-regression-seq-bin}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-linear-regression-seq-static-musl:hybrid$'
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
              ctest --output-on-failure -R '^phoenix-matrix-multiply-seq-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-matrix-multiply-static-musl-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-matrix-multiply-static-musl-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-matrix-multiply-seq-bin}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-matrix-multiply-seq-static-musl:hybrid$'
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
              ctest --output-on-failure -R '^phoenix-string-match-seq-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-string-match-static-musl-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-string-match-static-musl-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-string-match-seq-bin}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-string-match-seq-static-musl:hybrid$'
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
              ctest --output-on-failure -R '^phoenix-word-count-seq-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-word-count-static-musl-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-word-count-static-musl-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-word-count-seq-bin}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-word-count-seq-static-musl:hybrid$'
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
              ctest --output-on-failure -R '^phoenix-pca-seq-static-musl:dynamic$'
              runHook postCheck
            '';
            installPhase = ''
              mkdir -p "$out"
              touch "$out/passed"
            '';
          });
          phoenix-pca-static-musl-hybrid = arancini-package.overrideAttrs (old: {
            name = "arancini-phoenix-pca-static-musl-hybrid";
            cmakeFlags = old.cmakeFlags ++ [
              "-Dstatic-musl-phoenix-root=${phoenix-seq}"
            ];
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              ctest --output-on-failure -R '^phoenix-pca-seq-static-musl:hybrid$'
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
