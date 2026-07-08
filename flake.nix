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
        phoenix-mapreduce = phoenix.packages.${system}.phoenix-x86_64-musl-static-all;
        phoenix-musl-dynamic-seq-bin = phoenix-seq.overrideAttrs (_old: {
          name = "phoenix-x86_64-musl-dynamic-seq";
          dontPatchELF = true;
          dontFixup = true;
          hardeningDisable = [ "all" ];
          buildPhase = ''
            runHook preBuild
            cflags="-D_LINUX_ -D__x86_64__ -D_GNU_SOURCE -Wall -O2 -g -mno-avx -mno-avx2 -fno-tree-vectorize -fno-stack-protector -fno-PIE -no-pie"
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
        phoenix-musl-dynamic-pthread-bin = phoenix-pthread.overrideAttrs (_old: {
          name = "phoenix-x86_64-musl-dynamic-pthread";
          dontPatchELF = true;
          dontFixup = true;
          hardeningDisable = [ "all" ];
          buildPhase = ''
            runHook preBuild
            cflags="-D_LINUX_ -D__x86_64__ -D_GNU_SOURCE -Wall -O2 -g -mno-avx -mno-avx2 -fno-tree-vectorize -fno-stack-protector -fno-PIE -no-pie"
            cc="x86_64-unknown-linux-musl-gcc"
            ar="x86_64-unknown-linux-musl-ar"
            ranlib="x86_64-unknown-linux-musl-ranlib"
            make -C phoenix-2.0/src CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/histogram histogram-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/kmeans kmeans-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/linear_regression linear_regression-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/matrix_multiply matrix_multiply-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/string_match string_match-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/word_count word_count-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin" "$out/data"
            install -m755 phoenix-2.0/tests/histogram/histogram-pthread "$out/bin/histogram-pthread-v2"
            cp -p "$out/bin/histogram-pthread-v2" "$out/bin/histogram-pthread"
            install -m755 phoenix-2.0/tests/kmeans/kmeans-pthread "$out/bin/kmeans-pthread-v2"
            cp -p "$out/bin/kmeans-pthread-v2" "$out/bin/kmeans-pthread"
            install -m755 phoenix-2.0/tests/linear_regression/linear_regression-pthread "$out/bin/linear_regression-pthread-v2"
            cp -p "$out/bin/linear_regression-pthread-v2" "$out/bin/linear_regression-pthread"
            install -m755 phoenix-2.0/tests/matrix_multiply/matrix_multiply-pthread "$out/bin/matrix_multiply-pthread-v2"
            cp -p "$out/bin/matrix_multiply-pthread-v2" "$out/bin/matrix_multiply-pthread"
            install -m755 phoenix-2.0/tests/string_match/string_match-pthread "$out/bin/string_match-pthread-v2"
            cp -p "$out/bin/string_match-pthread-v2" "$out/bin/string_match-pthread"
            install -m755 phoenix-2.0/tests/word_count/word_count-pthread "$out/bin/word_count-pthread-v2"
            cp -p "$out/bin/word_count-pthread-v2" "$out/bin/word_count-pthread"
            cp -a ${phoenix-pthread}/data/. "$out/data/"
            runHook postInstall
          '';
        });
        phoenix-musl-dynamic-pthread =
          phoenix.packages.${system}.phoenix-x86_64-musl-dynamic-all
            or phoenix-musl-dynamic-pthread-bin;
        phoenix-musl-dynamic-pthread-pca-bin = phoenix-pthread.overrideAttrs (_old: {
          name = "phoenix-x86_64-musl-dynamic-pthread-pca";
          dontPatchELF = true;
          dontFixup = true;
          hardeningDisable = [ "all" ];
          buildPhase = ''
            runHook preBuild
            cflags="-D_LINUX_ -D__x86_64__ -D_GNU_SOURCE -Wall -O2 -g -mno-avx -mno-avx2 -fno-tree-vectorize -fno-stack-protector -fno-PIE -no-pie"
            cc="x86_64-unknown-linux-musl-gcc"
            ar="x86_64-unknown-linux-musl-ar"
            ranlib="x86_64-unknown-linux-musl-ranlib"
            make -C phoenix-2.0/src CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/pca pca-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin" "$out/data"
            install -m755 phoenix-2.0/tests/pca/pca-pthread "$out/bin/pca-pthread-v2"
            cp -p "$out/bin/pca-pthread-v2" "$out/bin/pca-pthread"
            cp -a ${phoenix-pthread}/data/. "$out/data/"
            runHook postInstall
          '';
        });
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
        phoenix-glibc-dynamic-pthread-bin = glibc-x86_64-pkgs.stdenv.mkDerivation {
          pname = "phoenix-x86_64-glibc-dynamic-pthread";
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
            substituteInPlace phoenix-2.0/tests/string_match/string_match-pthread.c \
              --replace-fail '#include <crypt.h>' '/* crypt.h unused */'
          '';
          buildPhase = ''
            runHook preBuild
            cflags="-D_LINUX_ -D__x86_64__ -D_GNU_SOURCE -Wall -O2 -g -mno-avx -mno-avx2 -fno-tree-vectorize -fno-stack-protector -fno-PIE -no-pie -pthread"
            cc="${glibc-x86_64-pkgs.stdenv.cc.targetPrefix}gcc"
            ar="${glibc-x86_64-pkgs.stdenv.cc.targetPrefix}ar"
            ranlib="${glibc-x86_64-pkgs.stdenv.cc.targetPrefix}ranlib"
            make -C phoenix-2.0/src CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            for app in histogram kmeans linear_regression matrix_multiply pca string_match word_count; do
              make -C "phoenix-2.0/tests/$app" "$app-pthread" \
                CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            done
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin" "$out/data"
            for app in histogram kmeans linear_regression matrix_multiply pca string_match word_count; do
              install -m755 "phoenix-2.0/tests/$app/$app-pthread" "$out/bin/$app-pthread-v2"
              cp -p "$out/bin/$app-pthread-v2" "$out/bin/$app-pthread"
            done
            cp -a ${phoenix-pthread}/data/. "$out/data/"
            runHook postInstall
          '';
        };
        phoenix-glibc-static-pthread-bin = glibc-x86_64-pkgs.stdenv.mkDerivation {
          pname = "phoenix-x86_64-glibc-static-pthread";
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
            substituteInPlace phoenix-2.0/tests/string_match/string_match-pthread.c \
              --replace-fail '#include <crypt.h>' '/* crypt.h unused */' \
              --replace-fail '    srand( (unsigned)time( NULL ) );' '    srand(1);' \
              --replace-fail '    gettimeofday(&starttime,0);' '    memset(&starttime, 0, sizeof(starttime));' \
              --replace-fail '    gettimeofday(&endtime,0);' '    memset(&endtime, 0, sizeof(endtime));'
            substituteInPlace phoenix-2.0/tests/word_count/word_count-pthread.c \
              --replace-fail '   gettimeofday(&starttime,0);' '   memset(&starttime, 0, sizeof(starttime));' \
              --replace-fail '   gettimeofday(&endtime,0);' '   memset(&endtime, 0, sizeof(endtime));' \
              --replace-fail '   return 0;
}' '   fflush(stdout);
   return 0;
}'
          '';
          buildPhase = ''
            runHook preBuild
            cflags="-D_LINUX_ -D__x86_64__ -D_GNU_SOURCE -Wall -O2 -g -fno-PIE -mno-avx -mno-avx2 -fno-tree-vectorize -fno-stack-protector -pthread -L${glibc-x86_64-pkgs.glibc.static}/lib"
            cc="${glibc-x86_64-pkgs.stdenv.cc.targetPrefix}gcc -static -no-pie"
            ar="${glibc-x86_64-pkgs.stdenv.cc.targetPrefix}ar"
            ranlib="${glibc-x86_64-pkgs.stdenv.cc.targetPrefix}ranlib"
            make -C phoenix-2.0/src CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/histogram histogram-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/kmeans kmeans-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/linear_regression linear_regression-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/matrix_multiply matrix_multiply-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/pca pca-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/string_match string_match-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            make -C phoenix-2.0/tests/word_count word_count-pthread \
              CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS="$cflags"
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin" "$out/data"
            install -m755 phoenix-2.0/tests/histogram/histogram-pthread \
              "$out/bin/histogram-pthread-v2-static-glibc"
            cp -p "$out/bin/histogram-pthread-v2-static-glibc" \
              "$out/bin/histogram-pthread-static-glibc"
            install -m755 phoenix-2.0/tests/kmeans/kmeans-pthread \
              "$out/bin/kmeans-pthread-v2-static-glibc"
            cp -p "$out/bin/kmeans-pthread-v2-static-glibc" \
              "$out/bin/kmeans-pthread-static-glibc"
            install -m755 phoenix-2.0/tests/linear_regression/linear_regression-pthread \
              "$out/bin/linear_regression-pthread-v2-static-glibc"
            cp -p "$out/bin/linear_regression-pthread-v2-static-glibc" \
              "$out/bin/linear_regression-pthread-static-glibc"
            install -m755 phoenix-2.0/tests/matrix_multiply/matrix_multiply-pthread \
              "$out/bin/matrix_multiply-pthread-v2-static-glibc"
            cp -p "$out/bin/matrix_multiply-pthread-v2-static-glibc" \
              "$out/bin/matrix_multiply-pthread-static-glibc"
            install -m755 phoenix-2.0/tests/pca/pca-pthread \
              "$out/bin/pca-pthread-v2-static-glibc"
            cp -p "$out/bin/pca-pthread-v2-static-glibc" \
              "$out/bin/pca-pthread-static-glibc"
            install -m755 phoenix-2.0/tests/string_match/string_match-pthread \
              "$out/bin/string_match-pthread-v2-static-glibc"
            cp -p "$out/bin/string_match-pthread-v2-static-glibc" \
              "$out/bin/string_match-pthread-static-glibc"
            install -m755 phoenix-2.0/tests/word_count/word_count-pthread \
              "$out/bin/word_count-pthread-v2-static-glibc"
            cp -p "$out/bin/word_count-pthread-v2-static-glibc" \
              "$out/bin/word_count-pthread-static-glibc"
            cp -a ${phoenix-pthread}/data/. "$out/data/"
            runHook postInstall
          '';
        };
        phoenix-glibc-static-pthread =
          phoenix.packages.${system}.phoenix-x86_64-glibc-static-pthread
            or phoenix-glibc-static-pthread-bin;
        phoenix-glibc-dynamic-pthread =
          phoenix.packages.${system}.phoenix-x86_64-glibc-dynamic-pthread
            or phoenix-glibc-dynamic-pthread-bin;
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
        mkPhoenixCheck =
          {
            name,
            cmakeFlags ? [ ],
            testRegex,
          }:
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

              cmake -S test-src -B build ${native_pkgs.lib.escapeShellArgs cmakeFlags}
              ctest --test-dir build --output-on-failure -R ${native_pkgs.lib.escapeShellArg testRegex}

              mkdir -p "$out"
              touch "$out/passed"

              runHook postBuild
            '';
      in
      {
        defaultPackage = arancini-package;
        checks = native_pkgs.lib.optionalAttrs (system == "aarch64-linux") {
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
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread-bin}"
            ];
            testRegex = "^phoenix-linear-regression-pthread-static-glibc:dynamic$";
          };
          phoenix-matrix-multiply-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread-bin}"
            ];
            testRegex = "^phoenix-matrix-multiply-pthread-static-glibc:dynamic$";
          };
          phoenix-pca-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread-bin}"
            ];
            testRegex = "^phoenix-pca-pthread-static-glibc:dynamic$";
          };
          phoenix-string-match-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread-bin}"
            ];
            testRegex = "^phoenix-string-match-pthread-static-glibc:dynamic$";
          };
          phoenix-word-count-pthread-static-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-pthread-static-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-glibc-pthread-phoenix-root=${phoenix-glibc-static-pthread-bin}"
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
              "-Ddynamic-musl-pthread-phoenix-root=${phoenix-musl-dynamic-pthread-pca-bin}"
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
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-histogram-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-histogram-seq-glibc:dynamic$";
          };
          phoenix-histogram-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-histogram-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-histogram-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-histogram-seq-glibc:hybrid$";
          };
          phoenix-kmeans-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-kmeans-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-kmeans-seq-glibc:dynamic$";
          };
          phoenix-kmeans-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-kmeans-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-kmeans-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-kmeans-seq-glibc:hybrid$";
          };
          phoenix-linear-regression-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-linear-regression-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-linear-regression-seq-glibc:dynamic$";
          };
          phoenix-linear-regression-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-linear-regression-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-linear-regression-seq-glibc:hybrid$";
          };
          phoenix-matrix-multiply-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-matrix-multiply-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-glibc:dynamic$";
          };
          phoenix-matrix-multiply-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-matrix-multiply-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-glibc:hybrid$";
          };
          phoenix-pca-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-pca-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-pca-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-pca-seq-glibc:dynamic$";
          };
          phoenix-pca-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-pca-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-pca-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-pca-seq-glibc:hybrid$";
          };
          phoenix-string-match-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-string-match-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-string-match-seq-glibc:dynamic$";
          };
          phoenix-string-match-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-string-match-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-string-match-seq-glibc:hybrid$";
          };
          phoenix-word-count-glibc-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-glibc-dynamic-no-static";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-word-count-seq}"
              "-Dhost-libatomic-libdir=:${native_pkgs.stdenv.cc.cc.lib}/lib"
            ];
            testRegex = "^phoenix-word-count-seq-glibc:dynamic$";
          };
          phoenix-word-count-glibc-dynamic-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-glibc-dynamic-hybrid";
            cmakeFlags = [
              "-Ddynamic-phoenix-root=${phoenix-glibc-dynamic-word-count-seq}"
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
              "-Dstatic-musl-phoenix-root=${phoenix-linear-regression-seq-bin}"
            ];
            testRegex = "^phoenix-linear-regression-seq-static-musl:dynamic$";
          };
          phoenix-linear-regression-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-linear-regression-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-linear-regression-seq-bin}"
            ];
            testRegex = "^phoenix-linear-regression-seq-static-musl:hybrid$";
          };
          phoenix-matrix-multiply-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-matrix-multiply-seq-bin}"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-static-musl:dynamic$";
          };
          phoenix-matrix-multiply-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-matrix-multiply-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-matrix-multiply-seq-bin}"
            ];
            testRegex = "^phoenix-matrix-multiply-seq-static-musl:hybrid$";
          };
          phoenix-string-match-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-string-match-seq-bin}"
            ];
            testRegex = "^phoenix-string-match-seq-static-musl:dynamic$";
          };
          phoenix-string-match-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-string-match-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-string-match-seq-bin}"
            ];
            testRegex = "^phoenix-string-match-seq-static-musl:hybrid$";
          };
          phoenix-word-count-dynamic-no-static = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-dynamic-no-static";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-word-count-seq-bin}"
            ];
            testRegex = "^phoenix-word-count-seq-static-musl:dynamic$";
          };
          phoenix-word-count-static-musl-hybrid = mkPhoenixCheck {
            name = "arancini-phoenix-word-count-static-musl-hybrid";
            cmakeFlags = [
              "-Dstatic-musl-phoenix-root=${phoenix-word-count-seq-bin}"
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
