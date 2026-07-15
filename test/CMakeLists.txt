cmake_minimum_required(VERSION 3.22)
project(arancini-tests LANGUAGES C ASM)

find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(tester "${Python3_EXECUTABLE}"
           "${CMAKE_CURRENT_LIST_DIR}/translate-and-run.py")

function(add_phoenix_hybrid_test testname input_bin config workdir)
  add_test(
    NAME "${testname}:hybrid"
    COMMAND ${tester} --drop-compile-flag=--no-static -t
            "$<TARGET_FILE:txlat>" -i "${input_bin}" -c "${config}"
            --log-level INFO)
  set_tests_properties("${testname}:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${workdir}")
endfunction()

function(add_phoenix_dynamic_and_hybrid_tests testname input_bin config workdir)
  add_test(
    NAME "${testname}:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${input_bin}" -c
            "${config}" --log-level INFO)
  set_tests_properties("${testname}:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${workdir}")
  add_phoenix_hybrid_test("${testname}" "${input_bin}" "${config}"
                          "${workdir}")
endfunction()

set(static-musl-phoenix-path
    "share/static-musl-phoenix"
    CACHE PATH "Path to static-musl-phoenix executables")
set(static-musl-phoenix-root
    ""
    CACHE PATH "Path to Phoenix x86_64 musl static package root (with bin/ and data/)")
set(static-musl-pthread-phoenix-root
    ""
    CACHE PATH "Path to Phoenix x86_64 musl static pthread package root (with bin/ and data/)")
set(static-musl-mapreduce-phoenix-root
    ""
    CACHE PATH "Path to Phoenix x86_64 musl static mapreduce package root (with bin/ and data/)")
set(static-glibc-pthread-phoenix-root
    ""
    CACHE PATH "Path to Phoenix x86_64 glibc static pthread package root (with bin/ and data/)")
set(dynamic-phoenix-root
    ""
    CACHE PATH "Path to dynamically linked Phoenix x86_64 package root (with bin/)")
set(dynamic-musl-phoenix-root
    ""
    CACHE PATH "Path to dynamically linked Phoenix x86_64 musl package root (with bin/ and data/)")
set(dynamic-musl-pthread-phoenix-root
    ""
    CACHE PATH "Path to dynamically linked Phoenix x86_64 musl pthread package root (with bin/ and data/)")
set(dynamic-glibc-pthread-phoenix-root
    ""
    CACHE PATH "Path to dynamically linked Phoenix x86_64 glibc pthread package root (with bin/ and data/)")
set(host-libatomic-libdir
    ""
    CACHE PATH "Path to host libatomic directory for translated test executables")

set(smoke-tests
    hello-world/hello-static-musl
    "${static-musl-phoenix-path}/histogram-seq-static-musl"
    "${static-musl-phoenix-path}/kmeans-seq-static-musl"
    "${static-musl-phoenix-path}/linear_regression-seq"
    "${static-musl-phoenix-path}/matrix_multiple-seq-static-musl"
    "${static-musl-phoenix-path}/pca-seq-static-musl"
    "${static-musl-phoenix-path}/string_match-seq-static-musl"
    "${static-musl-phoenix-path}/word_count-seq-static-musl")

foreach(test ${smoke-tests})
  get_filename_component(filename "${test}" NAME)

  # Find all config files for the given test
  file(GLOB configs "${test}.*.json")

  foreach(config ${configs})
    # Get config suffix (for test name)
    get_filename_component(config-filename "${config}" NAME_WLE)
    string(REPLACE "${filename}." "" suffix "${config-filename}")

    set(testname "${filename}:${suffix}")

    add_test(
      NAME "${testname}"
      COMMAND
        ${tester} -t "$<TARGET_FILE:txlat>" -i
        "${CMAKE_CURRENT_LIST_DIR}/${test}" -c "${config}" --log-level DEBUG)

    # Ensure that each test completes in at most 180 seconds (3 minutes)
    set_tests_properties("${testname}" PROPERTIES TIMEOUT 180)
  endforeach()
endforeach()

if(static-musl-phoenix-root)
  set(phoenix-histogram-bin
      "${static-musl-phoenix-root}/bin/histogram-seq-static-musl")
  set(phoenix-histogram-input
      "${static-musl-phoenix-root}/data/histogram_datafiles/small.bmp")
  set(phoenix-histogram-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-seq-static-musl.dynamic.json")
  set(phoenix-histogram-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-seq-static-musl.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-histogram-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-input}\"],\n    \"expected_stdout_sha256\": \"4b02b4c41e249a40a2acf92fd2bb32617318833b766d143d0cf135dc850b4deb\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-histogram-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-input}\"],\n    \"expected_stdout_sha256\": \"4b02b4c41e249a40a2acf92fd2bb32617318833b766d143d0cf135dc850b4deb\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-histogram-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-histogram-bin}"
            -c "${phoenix-histogram-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-histogram-seq-static-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-histogram-bin}"
            -c "${phoenix-histogram-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-seq-static-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-bin "${static-musl-phoenix-root}/bin/kmeans-seq-static-musl")
  set(phoenix-kmeans-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-seq-static-musl.dynamic.json")
  set(phoenix-kmeans-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-seq-static-musl.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"2100bc36e823308a3f392e216fbdde94c79c012c0aa47a139c6b3afd66c39e7f\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"2100bc36e823308a3f392e216fbdde94c79c012c0aa47a139c6b3afd66c39e7f\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-kmeans-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-kmeans-bin}" -c
            "${phoenix-kmeans-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-kmeans-seq-static-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-kmeans-bin}" -c
            "${phoenix-kmeans-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-seq-static-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-bin
      "${static-musl-phoenix-root}/bin/linear_regression-seq-static-musl")
  set(phoenix-linear-regression-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-small.txt")
  set(phoenix-linear-regression-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-seq-static-musl.dynamic.json")
  set(phoenix-linear-regression-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-seq-static-musl.hybrid.json")
  set(phoenix-linear-regression-hybrid-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-seq-static-musl.hybrid.nlib")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-input}"
    CONTENT "1 2\n2 4\n3 6\n4 8\n")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-input}\"],\n    \"expected_stdout_sha256\": \"9f369a68eb8d761dfe6d725c40323f40d89a0deb3d11c3d8259beb31f855a282\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(WRITE "${phoenix-linear-regression-hybrid-nlib}"
       "i32 printf(ptr fmt);\n")
  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-linear-regression-hybrid-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-input}\"],\n    \"expected_stdout_sha256\": \"1b6c00d9792bd06509c871002938a5dbd9684128304883fa34e9c980237bc915\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-linear-regression-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-bin}" -c
            "${phoenix-linear-regression-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-linear-regression-seq-static-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-bin}" -c
            "${phoenix-linear-regression-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-seq-static-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-matrix-multiply-bin
      "${static-musl-phoenix-root}/bin/matrix_multiply-seq-static-musl")
  set(phoenix-matrix-multiply-workdir
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-workdir")
  set(phoenix-matrix-multiply-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-seq-static-musl.dynamic.json")
  set(phoenix-matrix-multiply-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-seq-static-musl.hybrid.json")

  file(MAKE_DIRECTORY "${phoenix-matrix-multiply-workdir}")
  configure_file("${CMAKE_SOURCE_DIR}/aarch64.exec.lds"
                 "${phoenix-matrix-multiply-workdir}/aarch64.exec.lds" COPYONLY)
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "import pathlib, struct; d = pathlib.Path(r'${phoenix-matrix-multiply-workdir}'); (d / 'matrix_file_A.txt').write_bytes(struct.pack('<4i', 1, 2, 3, 4)); (d / 'matrix_file_B.txt').write_bytes(struct.pack('<4i', 5, 6, 7, 8))")

  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"2\"],\n    \"expected_stdout_sha256\": \"cda1ae0002bb95b50ac96c14369a3161858a2e53a5fd24f28769be9fbeb74a8b\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"2\"],\n    \"expected_stdout_sha256\": \"cda1ae0002bb95b50ac96c14369a3161858a2e53a5fd24f28769be9fbeb74a8b\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-matrix-multiply-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-bin}" -c
            "${phoenix-matrix-multiply-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${phoenix-matrix-multiply-workdir}")

  add_test(
    NAME "phoenix-matrix-multiply-seq-static-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-bin}" -c
            "${phoenix-matrix-multiply-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-seq-static-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${phoenix-matrix-multiply-workdir}")

  set(phoenix-string-match-bin
      "${static-musl-phoenix-root}/bin/string_match-seq-static-musl")
  set(phoenix-string-match-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-small.txt")
  set(phoenix-string-match-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-seq-static-musl.dynamic.json")
  set(phoenix-string-match-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-seq-static-musl.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-input}"
    CONTENT "abc\ndef\nfoo\nbar\n")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-input}\"],\n    \"expected_stdout_sha256\": \"d3e6d6d2b99677ad4b816a27cec01ee4c604ffc70d3d8c504948201bc8270599\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-string-match-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-input}\"],\n    \"expected_stdout_sha256\": \"d3e6d6d2b99677ad4b816a27cec01ee4c604ffc70d3d8c504948201bc8270599\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-string-match-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-bin}" -c
            "${phoenix-string-match-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-string-match-seq-static-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-bin}" -c
            "${phoenix-string-match-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-seq-static-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-word-count-bin
      "${static-musl-phoenix-root}/bin/word_count-seq-static-musl")
  set(phoenix-word-count-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-small.txt")
  set(phoenix-word-count-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-seq-static-musl.dynamic.json")
  set(phoenix-word-count-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-seq-static-musl.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-input}"
    CONTENT "apple banana apple cherry banana date\n")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-input}\"],\n    \"expected_stdout_sha256\": \"eb28dcfcae8b1cc370c392809ed8bfc5e130724ec74c9a407545582bf282d5be\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-word-count-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-input}\"],\n    \"expected_stdout_sha256\": \"eb28dcfcae8b1cc370c392809ed8bfc5e130724ec74c9a407545582bf282d5be\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-word-count-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-bin}" -c
            "${phoenix-word-count-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-word-count-seq-static-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-bin}" -c
            "${phoenix-word-count-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-seq-static-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-pca-bin "${static-musl-phoenix-root}/bin/pca-seq-static-musl")
  set(phoenix-pca-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-seq-static-musl.dynamic.json")
  set(phoenix-pca-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-seq-static-musl.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-pca-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"bf18326b07306e4afbef0464192844e43b993f4e08d7e27cb120394943d7c8bc\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-pca-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"1\"],\n    \"expected_stdout_sha256\": \"cfef00e885337ad5b5c3be804439d43c0baabbcce03f0b7ec3a0b9e2e743bd40\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-pca-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-pca-bin}" -c
            "${phoenix-pca-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-pca-seq-static-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-pca-bin}" -c
            "${phoenix-pca-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-seq-static-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
endif()

if(static-musl-pthread-phoenix-root)
  set(phoenix-histogram-pthread-bin
      "${static-musl-pthread-phoenix-root}/bin/histogram-pthread-static-musl")
  set(phoenix-histogram-pthread-input
      "${static-musl-pthread-phoenix-root}/data/histogram_datafiles/small.bmp")
  set(phoenix-histogram-pthread-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-pthread-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-histogram-pthread-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-pthread-input}\"],\n    \"expected_stdout_sha256\": \"1db37aab2f6bfb687f45c82c8d19287b5c4495215f7129fd7d05d9658c3ae060\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-histogram-pthread-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-histogram-pthread-bin}" -c
            "${phoenix-histogram-pthread-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-pthread-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-histogram-pthread-static-musl" "${phoenix-histogram-pthread-bin}"
    "${phoenix-histogram-pthread-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-histogram-pthread-v2-bin
      "${static-musl-pthread-phoenix-root}/bin/histogram-pthread-v2-static-musl")
  set(phoenix-histogram-pthread-v2-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-pthread-v2-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-histogram-pthread-v2-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-pthread-input}\"],\n    \"expected_stdout_sha256\": \"1db37aab2f6bfb687f45c82c8d19287b5c4495215f7129fd7d05d9658c3ae060\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-histogram-pthread-v2-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-histogram-pthread-v2-bin}" -c
            "${phoenix-histogram-pthread-v2-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-pthread-v2-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-histogram-pthread-v2-static-musl"
    "${phoenix-histogram-pthread-v2-bin}"
    "${phoenix-histogram-pthread-v2-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-pthread-bin
      "${static-musl-pthread-phoenix-root}/bin/kmeans-pthread-static-musl")
  set(phoenix-kmeans-pthread-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-pthread-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-pthread-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"d6791d3fba43f4b37ae1403fc41b1a7e6a7d545df57c96c90761361688f93c05\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-kmeans-pthread-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-kmeans-pthread-bin}" -c
            "${phoenix-kmeans-pthread-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-pthread-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-kmeans-pthread-static-musl" "${phoenix-kmeans-pthread-bin}"
    "${phoenix-kmeans-pthread-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-pthread-v2-bin
      "${static-musl-pthread-phoenix-root}/bin/kmeans-pthread-v2-static-musl")
  set(phoenix-kmeans-pthread-v2-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-pthread-v2-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-pthread-v2-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"d6791d3fba43f4b37ae1403fc41b1a7e6a7d545df57c96c90761361688f93c05\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-kmeans-pthread-v2-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-kmeans-pthread-v2-bin}" -c
            "${phoenix-kmeans-pthread-v2-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-pthread-v2-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-kmeans-pthread-v2-static-musl" "${phoenix-kmeans-pthread-v2-bin}"
    "${phoenix-kmeans-pthread-v2-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-pthread-bin
      "${static-musl-pthread-phoenix-root}/bin/linear_regression-pthread-static-musl")
  set(phoenix-linear-regression-pthread-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-small.bin")
  set(phoenix-linear-regression-pthread-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-static-musl.dynamic.json")

  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "from pathlib import Path; Path(r'${phoenix-linear-regression-pthread-input}').write_bytes(bytes([1, 2, 2, 4, 3, 6, 4, 8]))")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-pthread-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-pthread-input}\"],\n    \"expected_stdout_sha256\": \"dbecd56c39fd6c5a577c7988b0fc133e84d2ba945a88ca2fe9fd0410499aa74d\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-linear-regression-pthread-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-pthread-bin}" -c
            "${phoenix-linear-regression-pthread-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-pthread-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-linear-regression-pthread-static-musl"
    "${phoenix-linear-regression-pthread-bin}"
    "${phoenix-linear-regression-pthread-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-pthread-v2-bin
      "${static-musl-pthread-phoenix-root}/bin/linear_regression-pthread-v2-static-musl")
  set(phoenix-linear-regression-pthread-v2-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-v2-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-pthread-v2-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-pthread-input}\"],\n    \"expected_stdout_sha256\": \"dbecd56c39fd6c5a577c7988b0fc133e84d2ba945a88ca2fe9fd0410499aa74d\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-linear-regression-pthread-v2-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-pthread-v2-bin}" -c
            "${phoenix-linear-regression-pthread-v2-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-pthread-v2-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-linear-regression-pthread-v2-static-musl"
    "${phoenix-linear-regression-pthread-v2-bin}"
    "${phoenix-linear-regression-pthread-v2-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-matrix-multiply-pthread-bin
      "${static-musl-pthread-phoenix-root}/bin/matrix_multiply-pthread-static-musl")
  set(phoenix-matrix-multiply-pthread-v2-bin
      "${static-musl-pthread-phoenix-root}/bin/matrix_multiply-pthread-v2-static-musl")
  set(phoenix-matrix-multiply-pthread-workdir
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-workdir")
  set(phoenix-matrix-multiply-pthread-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-static-musl.dynamic.json")
  set(phoenix-matrix-multiply-pthread-v2-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-v2-static-musl.dynamic.json")

  file(MAKE_DIRECTORY "${phoenix-matrix-multiply-pthread-workdir}")
  configure_file(
    "${CMAKE_SOURCE_DIR}/aarch64.exec.lds"
    "${phoenix-matrix-multiply-pthread-workdir}/aarch64.exec.lds" COPYONLY)
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "import pathlib; d = pathlib.Path(r'${phoenix-matrix-multiply-pthread-workdir}'); data = bytes(32 * 32 * 4); (d / 'matrix_file_A.txt').write_bytes(data); (d / 'matrix_file_B.txt').write_bytes(data)")

  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-pthread-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"32\"],\n    \"expected_stdout_sha256\": \"f0b05f66263dd77dfeafbcf7ff7704c56c913e7eb730e44385f22b6b79cbe1b3\",\n    \"expected_stderr_sha256\": \"23aab5596dacb17bb8e82fa96b660b092e5739383bc8fcecd731db46448e2f71\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-pthread-v2-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"32\"],\n    \"expected_stdout_sha256\": \"f0b05f66263dd77dfeafbcf7ff7704c56c913e7eb730e44385f22b6b79cbe1b3\",\n    \"expected_stderr_sha256\": \"23aab5596dacb17bb8e82fa96b660b092e5739383bc8fcecd731db46448e2f71\"\n}\n")

  add_test(
    NAME "phoenix-matrix-multiply-pthread-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-pthread-bin}" -c
            "${phoenix-matrix-multiply-pthread-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-pthread-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY
                                    "${phoenix-matrix-multiply-pthread-workdir}")
  add_phoenix_hybrid_test(
    "phoenix-matrix-multiply-pthread-static-musl"
    "${phoenix-matrix-multiply-pthread-bin}"
    "${phoenix-matrix-multiply-pthread-config}"
    "${phoenix-matrix-multiply-pthread-workdir}")

  add_test(
    NAME "phoenix-matrix-multiply-pthread-v2-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-pthread-v2-bin}" -c
            "${phoenix-matrix-multiply-pthread-v2-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-pthread-v2-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY
                                    "${phoenix-matrix-multiply-pthread-workdir}")
  add_phoenix_hybrid_test(
    "phoenix-matrix-multiply-pthread-v2-static-musl"
    "${phoenix-matrix-multiply-pthread-v2-bin}"
    "${phoenix-matrix-multiply-pthread-v2-config}"
    "${phoenix-matrix-multiply-pthread-workdir}")

  set(phoenix-pca-pthread-bin
      "${static-musl-pthread-phoenix-root}/bin/pca-pthread-static-musl")
  set(phoenix-pca-pthread-v2-bin
      "${static-musl-pthread-phoenix-root}/bin/pca-pthread-v2-static-musl")
  set(phoenix-pca-pthread-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-pthread-static-musl.dynamic.json")
  set(phoenix-pca-pthread-v2-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-pthread-v2-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-pca-pthread-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"fc9302f98b583a32026aa92846b3f26a929f50c6133679b833d3137b96802f31\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-pca-pthread-v2-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"fc9302f98b583a32026aa92846b3f26a929f50c6133679b833d3137b96802f31\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-pca-pthread-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-pca-pthread-bin}"
            -c "${phoenix-pca-pthread-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-pthread-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-pca-pthread-static-musl" "${phoenix-pca-pthread-bin}"
    "${phoenix-pca-pthread-config}" "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-pca-pthread-v2-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-pca-pthread-v2-bin}" -c
            "${phoenix-pca-pthread-v2-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-pthread-v2-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-pca-pthread-v2-static-musl" "${phoenix-pca-pthread-v2-bin}"
    "${phoenix-pca-pthread-v2-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-string-match-pthread-bin
      "${static-musl-pthread-phoenix-root}/bin/string_match-pthread-static-musl")
  set(phoenix-string-match-pthread-v2-bin
      "${static-musl-pthread-phoenix-root}/bin/string_match-pthread-v2-static-musl")
  # The manifest's 50MB string_match input makes elapsed-time stdout unstable;
  # use a tiny deterministic input for hash-stable regression testing.
  set(phoenix-string-match-pthread-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-small.txt")
  set(phoenix-string-match-pthread-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-static-musl.dynamic.json")
  set(phoenix-string-match-pthread-v2-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-v2-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-pthread-input}"
    CONTENT "Helloworld\nhowareyou\nferrari\nwhotheman\n")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-pthread-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-pthread-input}\"],\n    \"expected_stdout_sha256\": \"e08f600b364500045cec207460953500ae4063d16f9324ff55d86d946a4663a4\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-string-match-pthread-v2-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-pthread-input}\"],\n    \"expected_stdout_sha256\": \"e08f600b364500045cec207460953500ae4063d16f9324ff55d86d946a4663a4\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-string-match-pthread-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-pthread-bin}" -c
            "${phoenix-string-match-pthread-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-pthread-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-string-match-pthread-static-musl"
    "${phoenix-string-match-pthread-bin}"
    "${phoenix-string-match-pthread-config}" "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-string-match-pthread-v2-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-pthread-v2-bin}" -c
            "${phoenix-string-match-pthread-v2-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-pthread-v2-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-string-match-pthread-v2-static-musl"
    "${phoenix-string-match-pthread-v2-bin}"
    "${phoenix-string-match-pthread-v2-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-word-count-pthread-bin
      "${static-musl-pthread-phoenix-root}/bin/word_count-pthread-static-musl")
  set(phoenix-word-count-pthread-v2-bin
      "${static-musl-pthread-phoenix-root}/bin/word_count-pthread-v2-static-musl")
  # The manifest's 10MB word_count input can make elapsed-time stdout unstable;
  # use a tiny deterministic input for hash-stable regression testing.
  set(phoenix-word-count-pthread-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-small.txt")
  set(phoenix-word-count-pthread-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-static-musl.dynamic.json")
  set(phoenix-word-count-pthread-v2-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-v2-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-pthread-input}"
    CONTENT "alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha\nbeta beta beta beta beta beta beta beta beta beta beta\ngamma gamma gamma gamma gamma gamma gamma gamma gamma gamma\ndelta delta delta delta delta delta delta delta delta\nepsilon epsilon epsilon epsilon epsilon epsilon epsilon epsilon\nzeta zeta zeta zeta zeta zeta zeta\neta eta eta eta eta eta\ntheta theta theta theta theta\niota iota iota iota\nkappa kappa kappa\nlambda lambda\nmu\n")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-pthread-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-pthread-input}\"],\n    \"expected_stdout_sha256\": \"c3d5bdc3ccd8c218db22c40ca8a7e244baa602e45e590f22691e30ca06bb4197\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-word-count-pthread-v2-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-pthread-input}\"],\n    \"expected_stdout_sha256\": \"c3d5bdc3ccd8c218db22c40ca8a7e244baa602e45e590f22691e30ca06bb4197\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-word-count-pthread-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-pthread-bin}" -c
            "${phoenix-word-count-pthread-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-pthread-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-word-count-pthread-static-musl" "${phoenix-word-count-pthread-bin}"
    "${phoenix-word-count-pthread-config}" "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-word-count-pthread-v2-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-pthread-v2-bin}" -c
            "${phoenix-word-count-pthread-v2-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-pthread-v2-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-word-count-pthread-v2-static-musl"
    "${phoenix-word-count-pthread-v2-bin}"
    "${phoenix-word-count-pthread-v2-config}" "${CMAKE_SOURCE_DIR}")
endif()

if(static-musl-mapreduce-phoenix-root)
  set(phoenix-mapreduce-env "\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\",\n        \"MR_L1CACHESIZE\": \"8192\",\n        \"MR_NUMTHREADS\": \"1\",\n        \"MR_NUMPROCS\": \"1\",\n        \"MR_KEYMATCHFACTOR\": \"2\",\n        \"MR_1QPERTASK\": \"0\"\n")

  set(phoenix-histogram-mapreduce-bin
      "${static-musl-mapreduce-phoenix-root}/bin/histogram-static-musl")
  set(phoenix-histogram-mapreduce-input
      "${static-musl-mapreduce-phoenix-root}/data/histogram_datafiles/small.bmp")
  set(phoenix-histogram-mapreduce-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-mapreduce-static-musl.dynamic.json")
  file(
    GENERATE
    OUTPUT "${phoenix-histogram-mapreduce-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {${phoenix-mapreduce-env}    },\n    \"runtime_flags\": [\"${phoenix-histogram-mapreduce-input}\"],\n    \"expected_stdout_sha256\": \"45206bc85e222d09a74f7e1edcd50a5e786ca3124abc08aa6d29d73e210fa4d0\",\n    \"expected_stderr_sha256\": \"fa1b7e0916c71a25e173a9f960728b458d5cda613480c8be1fd6ba52d7be5eb5\"\n}\n")
  add_phoenix_dynamic_and_hybrid_tests(
    "phoenix-histogram-mapreduce-static-musl"
    "${phoenix-histogram-mapreduce-bin}"
    "${phoenix-histogram-mapreduce-config}" "${CMAKE_SOURCE_DIR}")
  set(phoenix-histogram-mapreduce-v2-bin
      "${static-musl-mapreduce-phoenix-root}/bin/histogram-v2-static-musl")
  add_phoenix_hybrid_test(
    "phoenix-histogram-mapreduce-v2-static-musl"
    "${phoenix-histogram-mapreduce-v2-bin}"
    "${phoenix-histogram-mapreduce-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-mapreduce-bin
      "${static-musl-mapreduce-phoenix-root}/bin/kmeans-static-musl")
  set(phoenix-kmeans-mapreduce-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-mapreduce-static-musl.dynamic.json")
  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-mapreduce-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {${phoenix-mapreduce-env}    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"af9d56e299227cd1890a9e1aa1170bbbc974e113ca82da4388a4eb0f05aade54\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_phoenix_dynamic_and_hybrid_tests(
    "phoenix-kmeans-mapreduce-static-musl" "${phoenix-kmeans-mapreduce-bin}"
    "${phoenix-kmeans-mapreduce-config}" "${CMAKE_SOURCE_DIR}")
  set(phoenix-kmeans-mapreduce-v2-bin
      "${static-musl-mapreduce-phoenix-root}/bin/kmeans-v2-static-musl")
  add_phoenix_hybrid_test(
    "phoenix-kmeans-mapreduce-v2-static-musl"
    "${phoenix-kmeans-mapreduce-v2-bin}" "${phoenix-kmeans-mapreduce-config}"
    "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-mapreduce-bin
      "${static-musl-mapreduce-phoenix-root}/bin/linear_regression-static-musl")
  set(phoenix-linear-regression-mapreduce-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-mapreduce-small.bin")
  set(phoenix-linear-regression-mapreduce-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-mapreduce-static-musl.dynamic.json")
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "from pathlib import Path; Path(r'${phoenix-linear-regression-mapreduce-input}').write_bytes(bytes([1, 2, 2, 4, 3, 6, 4, 8]))")
  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-mapreduce-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {${phoenix-mapreduce-env}    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-mapreduce-input}\"],\n    \"expected_stdout_sha256\": \"a1d50f2603f02d7d4046fb0b45a5c088befd3fa549102f2cb817111e8fc65302\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_test(
    NAME "phoenix-linear-regression-mapreduce-static-musl:dynamic"
    COMMAND
      ${tester} -t "$<TARGET_FILE:txlat>" -i
      "${phoenix-linear-regression-mapreduce-bin}" -c
      "${phoenix-linear-regression-mapreduce-config}" --log-level INFO
      --replace-stdout-for-sha256
      "^Linear Regression: Completed -?[0-9]+$"
      "Linear Regression: Completed 0")
  set_tests_properties(
    "phoenix-linear-regression-mapreduce-static-musl:dynamic"
    PROPERTIES TIMEOUT 180
               WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-linear-regression-mapreduce-static-musl"
    "${phoenix-linear-regression-mapreduce-bin}"
    "${phoenix-linear-regression-mapreduce-config}" "${CMAKE_SOURCE_DIR}")
  set(phoenix-linear-regression-mapreduce-v2-bin
      "${static-musl-mapreduce-phoenix-root}/bin/linear_regression-v2-static-musl")
  add_phoenix_hybrid_test(
    "phoenix-linear-regression-mapreduce-v2-static-musl"
    "${phoenix-linear-regression-mapreduce-v2-bin}"
    "${phoenix-linear-regression-mapreduce-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-matrix-multiply-mapreduce-bin
      "${static-musl-mapreduce-phoenix-root}/bin/matrix_multiply-static-musl")
  set(phoenix-matrix-multiply-mapreduce-workdir
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-mapreduce-workdir")
  set(phoenix-matrix-multiply-mapreduce-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-mapreduce-static-musl.dynamic.json")
  file(MAKE_DIRECTORY "${phoenix-matrix-multiply-mapreduce-workdir}")
  configure_file(
    "${CMAKE_SOURCE_DIR}/aarch64.exec.lds"
    "${phoenix-matrix-multiply-mapreduce-workdir}/aarch64.exec.lds" COPYONLY)
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "import pathlib; d = pathlib.Path(r'${phoenix-matrix-multiply-mapreduce-workdir}'); data = bytes(32 * 32 * 4); (d / 'matrix_file_A.txt').write_bytes(data); (d / 'matrix_file_B.txt').write_bytes(data)")
  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-mapreduce-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {${phoenix-mapreduce-env}    },\n    \"runtime_flags\": [\"32\", \"1\"],\n    \"expected_stdout_sha256\": \"a278d9ec2aa8df1a75ef72e16ed03960c7a8a90ea3f22d7424967af719472eb7\",\n    \"expected_stderr_sha256\": \"3afdddde6bd17de542151a0a75eac106ffd0477fdaab4c66d3832e107ebb82c4\"\n}\n")
  add_phoenix_dynamic_and_hybrid_tests(
    "phoenix-matrix-multiply-mapreduce-static-musl"
    "${phoenix-matrix-multiply-mapreduce-bin}"
    "${phoenix-matrix-multiply-mapreduce-config}"
    "${phoenix-matrix-multiply-mapreduce-workdir}")
  set(phoenix-matrix-multiply-mapreduce-v2-bin
      "${static-musl-mapreduce-phoenix-root}/bin/matrix_multiply-v2-static-musl")
  add_phoenix_hybrid_test(
    "phoenix-matrix-multiply-mapreduce-v2-static-musl"
    "${phoenix-matrix-multiply-mapreduce-v2-bin}"
    "${phoenix-matrix-multiply-mapreduce-config}"
    "${phoenix-matrix-multiply-mapreduce-workdir}")

  set(phoenix-pca-mapreduce-bin
      "${static-musl-mapreduce-phoenix-root}/bin/pca-static-musl")
  set(phoenix-pca-mapreduce-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-mapreduce-static-musl.dynamic.json")
  set(phoenix-pca-mapreduce-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-mapreduce-static-musl.hybrid.json")
  file(
    GENERATE
    OUTPUT "${phoenix-pca-mapreduce-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {${phoenix-mapreduce-env}    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"cde797f4a38a0aa4c16275aad5513ecdf646f25adf603b89a540a08fd7ad0db0\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-pca-mapreduce-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {${phoenix-mapreduce-env}    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"0826174a142f24fece8fa15a7dc832ada06f9fd7b2a0317910b83b9409cce2e1\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_test(
    NAME "phoenix-pca-mapreduce-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-pca-mapreduce-bin}"
            -c "${phoenix-pca-mapreduce-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-mapreduce-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
  add_phoenix_hybrid_test(
    "phoenix-pca-mapreduce-static-musl" "${phoenix-pca-mapreduce-bin}"
    "${phoenix-pca-mapreduce-hybrid-config}" "${CMAKE_SOURCE_DIR}")
  set(phoenix-pca-mapreduce-v2-bin
      "${static-musl-mapreduce-phoenix-root}/bin/pca-v2-static-musl")
  add_phoenix_hybrid_test(
    "phoenix-pca-mapreduce-v2-static-musl"
    "${phoenix-pca-mapreduce-v2-bin}"
    "${phoenix-pca-mapreduce-hybrid-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-string-match-mapreduce-bin
      "${static-musl-mapreduce-phoenix-root}/bin/string_match-static-musl")
  set(phoenix-string-match-mapreduce-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-mapreduce-small.txt")
  set(phoenix-string-match-mapreduce-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-mapreduce-static-musl.dynamic.json")
  file(
    GENERATE
    OUTPUT "${phoenix-string-match-mapreduce-input}"
    CONTENT "the quick brown fox jumps over the lazy dog\nthe fox was quick\n")
  file(
    GENERATE
    OUTPUT "${phoenix-string-match-mapreduce-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {${phoenix-mapreduce-env}    },\n    \"runtime_flags\": [\"${phoenix-string-match-mapreduce-input}\"],\n    \"expected_stdout_sha256\": \"58cbf9127013df3a665f2037f26e4da84be3bff2a42980d4ba98d8908402e67e\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_phoenix_dynamic_and_hybrid_tests(
    "phoenix-string-match-mapreduce-static-musl"
    "${phoenix-string-match-mapreduce-bin}"
    "${phoenix-string-match-mapreduce-config}" "${CMAKE_SOURCE_DIR}")
  set(phoenix-string-match-mapreduce-v2-bin
      "${static-musl-mapreduce-phoenix-root}/bin/string_match-v2-static-musl")
  add_phoenix_hybrid_test(
    "phoenix-string-match-mapreduce-v2-static-musl"
    "${phoenix-string-match-mapreduce-v2-bin}"
    "${phoenix-string-match-mapreduce-config}" "${CMAKE_SOURCE_DIR}")

  set(phoenix-word-count-mapreduce-bin
      "${static-musl-mapreduce-phoenix-root}/bin/word_count-static-musl")
  set(phoenix-word-count-mapreduce-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-mapreduce-small.txt")
  set(phoenix-word-count-mapreduce-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-mapreduce-static-musl.dynamic.json")
  file(
    GENERATE
    OUTPUT "${phoenix-word-count-mapreduce-input}"
    CONTENT "the quick brown fox jumps over the lazy dog\nthe fox was quick\n")
  file(
    GENERATE
    OUTPUT "${phoenix-word-count-mapreduce-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {${phoenix-mapreduce-env}    },\n    \"runtime_flags\": [\"${phoenix-word-count-mapreduce-input}\"],\n    \"expected_stdout_sha256\": \"8a2f826ebe551da875da911874019ae3e5e29e99dda768ed665a7bcc516bb4bf\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_phoenix_dynamic_and_hybrid_tests(
    "phoenix-word-count-mapreduce-static-musl"
    "${phoenix-word-count-mapreduce-bin}"
    "${phoenix-word-count-mapreduce-config}" "${CMAKE_SOURCE_DIR}")
  set(phoenix-word-count-mapreduce-v2-bin
      "${static-musl-mapreduce-phoenix-root}/bin/word_count-v2-static-musl")
  add_phoenix_hybrid_test(
    "phoenix-word-count-mapreduce-v2-static-musl"
    "${phoenix-word-count-mapreduce-v2-bin}"
    "${phoenix-word-count-mapreduce-config}" "${CMAKE_SOURCE_DIR}")
endif()

if(static-glibc-pthread-phoenix-root)
  set(phoenix-histogram-pthread-static-glibc-bin
      "${static-glibc-pthread-phoenix-root}/bin/histogram-pthread-static-glibc")
  set(phoenix-histogram-pthread-static-glibc-input
      "${static-glibc-pthread-phoenix-root}/data/histogram_datafiles/small.bmp")
  set(phoenix-histogram-pthread-static-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-pthread-static-glibc.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-histogram-pthread-static-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-pthread-static-glibc-input}\"],\n    \"expected_stdout_sha256\": \"1db37aab2f6bfb687f45c82c8d19287b5c4495215f7129fd7d05d9658c3ae060\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-histogram-pthread-static-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-histogram-pthread-static-glibc-bin}" -c
            "${phoenix-histogram-pthread-static-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-pthread-static-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-pthread-static-glibc-bin
      "${static-glibc-pthread-phoenix-root}/bin/kmeans-pthread-static-glibc")
  set(phoenix-kmeans-pthread-static-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-pthread-static-glibc.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-pthread-static-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"ea912f078bf2bf965726ab22703263dc8563c1f458c7c588e67c2805b35a27f9\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-kmeans-pthread-static-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-kmeans-pthread-static-glibc-bin}" -c
            "${phoenix-kmeans-pthread-static-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-pthread-static-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-pthread-static-glibc-bin
      "${static-glibc-pthread-phoenix-root}/bin/linear_regression-pthread-static-glibc")
  # Keep this consistent with the static-musl pthread regression: the manifest's
  # 50MB input is unnecessary here, and this tiny perfect-line data set gives
  # deterministic, hash-stable stdout with ARANCINI_GUEST_CPUS=1.
  set(phoenix-linear-regression-pthread-static-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-static-glibc-small.bin")
  set(phoenix-linear-regression-pthread-static-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-static-glibc.dynamic.json")

  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "from pathlib import Path; Path(r'${phoenix-linear-regression-pthread-static-glibc-input}').write_bytes(bytes([1, 2, 2, 4, 3, 6, 4, 8]))")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-pthread-static-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-pthread-static-glibc-input}\"],\n    \"expected_stdout_sha256\": \"dbecd56c39fd6c5a577c7988b0fc133e84d2ba945a88ca2fe9fd0410499aa74d\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-linear-regression-pthread-static-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-pthread-static-glibc-bin}" -c
            "${phoenix-linear-regression-pthread-static-glibc-config}"
            --log-level INFO)
  set_tests_properties("phoenix-linear-regression-pthread-static-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-matrix-multiply-pthread-static-glibc-bin
      "${static-glibc-pthread-phoenix-root}/bin/matrix_multiply-pthread-static-glibc")
  set(phoenix-matrix-multiply-pthread-static-glibc-workdir
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-static-glibc-workdir")
  set(phoenix-matrix-multiply-pthread-static-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-static-glibc.dynamic.json")

  file(MAKE_DIRECTORY "${phoenix-matrix-multiply-pthread-static-glibc-workdir}")
  configure_file(
    "${CMAKE_SOURCE_DIR}/aarch64.exec.lds"
    "${phoenix-matrix-multiply-pthread-static-glibc-workdir}/aarch64.exec.lds"
    COPYONLY)
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "import pathlib; d = pathlib.Path(r'${phoenix-matrix-multiply-pthread-static-glibc-workdir}'); data = bytes(32 * 32 * 4); (d / 'matrix_file_A.txt').write_bytes(data); (d / 'matrix_file_B.txt').write_bytes(data)")

  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-pthread-static-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"32\"],\n    \"expected_stdout_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-matrix-multiply-pthread-static-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-pthread-static-glibc-bin}" -c
            "${phoenix-matrix-multiply-pthread-static-glibc-config}"
            --log-level INFO)
  set_tests_properties(
    "phoenix-matrix-multiply-pthread-static-glibc:dynamic"
    PROPERTIES TIMEOUT 180
               WORKING_DIRECTORY
                 "${phoenix-matrix-multiply-pthread-static-glibc-workdir}")

  set(phoenix-pca-pthread-static-glibc-bin
      "${static-glibc-pthread-phoenix-root}/bin/pca-pthread-static-glibc")
  set(phoenix-pca-pthread-static-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-pthread-static-glibc.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-pca-pthread-static-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"13c945f40259f6e6230f714f1444e6301ae401acfe80b5259cef50f1b9d999cc\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-pca-pthread-static-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-pca-pthread-static-glibc-bin}" -c
            "${phoenix-pca-pthread-static-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-pthread-static-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-string-match-pthread-static-glibc-bin
      "${static-glibc-pthread-phoenix-root}/bin/string_match-pthread-static-glibc")
  # Keep this consistent with the static-musl pthread regression: the manifest's
  # 50MB input includes elapsed-time stdout and is unnecessarily slow; this tiny
  # deterministic input gives hash-stable stdout with ARANCINI_GUEST_CPUS=1.
  set(phoenix-string-match-pthread-static-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-static-glibc-small.txt")
  set(phoenix-string-match-pthread-static-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-static-glibc.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-pthread-static-glibc-input}"
    CONTENT "Helloworld\nhowareyou\nferrari\nwhotheman\n")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-pthread-static-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-pthread-static-glibc-input}\"],\n    \"expected_stdout_sha256\": \"e08f600b364500045cec207460953500ae4063d16f9324ff55d86d946a4663a4\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-string-match-pthread-static-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-pthread-static-glibc-bin}" -c
            "${phoenix-string-match-pthread-static-glibc-config}"
            --log-level INFO)
  set_tests_properties("phoenix-string-match-pthread-static-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-word-count-pthread-static-glibc-bin
      "${static-glibc-pthread-phoenix-root}/bin/word_count-pthread-static-glibc")
  # Keep this consistent with the static-musl pthread regression: the manifest's
  # 10MB input can make elapsed-time stdout unstable; use a tiny deterministic
  # input for hash-stable regression testing.
  set(phoenix-word-count-pthread-static-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-static-glibc-small.txt")
  set(phoenix-word-count-pthread-static-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-static-glibc.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-pthread-static-glibc-input}"
    CONTENT "alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha\nbeta beta beta beta beta beta beta beta beta beta beta\ngamma gamma gamma gamma gamma gamma gamma gamma gamma gamma\ndelta delta delta delta delta delta delta delta delta\nepsilon epsilon epsilon epsilon epsilon epsilon epsilon epsilon\nzeta zeta zeta zeta zeta zeta zeta\neta eta eta eta eta eta\ntheta theta theta theta theta\niota iota iota iota\nkappa kappa kappa\nlambda lambda\nmu\n")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-pthread-static-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-pthread-static-glibc-input}\"],\n    \"expected_stdout_sha256\": \"c3d5bdc3ccd8c218db22c40ca8a7e244baa602e45e590f22691e30ca06bb4197\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-word-count-pthread-static-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-pthread-static-glibc-bin}" -c
            "${phoenix-word-count-pthread-static-glibc-config}"
            --log-level INFO)
  set_tests_properties("phoenix-word-count-pthread-static-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
endif()

if(dynamic-glibc-pthread-phoenix-root)
  set(phoenix-pthread-glibc-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pthread-glibc.nlib")
  set(phoenix-pthread-glibc-stub-c
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pthread-glibc-stub.c")
  set(phoenix-pthread-glibc-stub
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pthread-glibc-stub.o")

  file(
    WRITE "${phoenix-pthread-glibc-stub-c}"
    "#define _GNU_SOURCE\n#include <sched.h>\n#include <stddef.h>\n#include <string.h>\n#include <sys/time.h>\n#include <time.h>\n#include <unistd.h>\nvoid __gmon_start__(void) {}\nint sched_getaffinity(pid_t pid, size_t cpusetsize, cpu_set_t *mask) { (void)pid; memset(mask, 0, cpusetsize); if (cpusetsize >= sizeof(unsigned long)) ((unsigned long *)mask)[0] = 1ul; return 0; }\nlong sysconf(int name) { (void)name; return 1; }\nint gettimeofday(struct timeval *tv, void *tz) { (void)tz; if (tv) { tv->tv_sec = 0; tv->tv_usec = 0; } return 0; }\ntime_t time(time_t *tloc) { if (tloc) *tloc = 1; return 1; }\n")
  execute_process(
    COMMAND "${CMAKE_C_COMPILER}" -c "${phoenix-pthread-glibc-stub-c}" -o
            "${phoenix-pthread-glibc-stub}")

  file(
    WRITE "${phoenix-pthread-glibc-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "void exit(i32 status);\n"
    "void perror(ptr s);\n"
    "ptr malloc(u64 size);\n"
    "ptr calloc(u64 nmemb, u64 size);\n"
    "ptr realloc(ptr p, u64 size);\n"
    "void free(ptr p);\n"
    "ptr memcpy(ptr dest, ptr src, u64 n);\n"
    "ptr memmove(ptr dest, ptr src, u64 n);\n"
    "ptr memset(ptr s, i32 c, u64 n);\n"
    "i32 strcmp(ptr a, ptr b);\n"
    "u64 strlen(ptr s);\n"
    "ptr __ctype_toupper_loc();\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i64 write(i32 filedesc, ptr buf, u64 count);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i32 fflush(ptr stream);\n"
    "i64 __isoc23_strtol(ptr nptr, ptr endptr, i32 base);\n"
    "i32 getopt(i32 argc, ptr argv, ptr optstring);\n"
    "void srand(u32 seed);\n"
    "i32 rand();\n"
    "void qsort(ptr base, u64 nmemb, u64 size, ptr compar);\n"
    "i32 pthread_attr_init(ptr attr);\n"
    "i32 pthread_attr_setscope(ptr attr, i32 scope);\n"
    "i32 pthread_attr_destroy(ptr attr);\n"
    "i32 pthread_create(ptr thread, ptr attr, ptr start_routine, ptr arg);\n"
    "i32 pthread_join(u64 thread, ptr retval);\n"
    "i32 pthread_mutex_init(ptr mutex, ptr attr);\n"
    "i32 pthread_mutex_lock(ptr mutex);\n"
    "i32 pthread_mutex_unlock(ptr mutex);\n"
    "library \"${phoenix-pthread-glibc-stub}\";\n"
    "void __gmon_start__();\n"
    "i32 sched_getaffinity(i32 pid, u64 cpusetsize, ptr mask);\n"
    "i64 sysconf(i32 name);\n"
    "i32 gettimeofday(ptr tv, ptr tz);\n"
    "i64 time(ptr tloc);\n")

  set(phoenix-histogram-pthread-glibc-bin
      "${dynamic-glibc-pthread-phoenix-root}/bin/histogram-pthread-v2")
  set(phoenix-histogram-pthread-glibc-input
      "${dynamic-glibc-pthread-phoenix-root}/data/histogram_datafiles/small.bmp")
  set(phoenix-histogram-pthread-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-pthread-glibc.dynamic.json")
  file(
    GENERATE
    OUTPUT "${phoenix-histogram-pthread-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pthread-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-pthread-glibc-input}\"],\n    \"expected_stdout_sha256\": \"1db37aab2f6bfb687f45c82c8d19287b5c4495215f7129fd7d05d9658c3ae060\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_test(
    NAME "phoenix-histogram-pthread-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-histogram-pthread-glibc-bin}" -c
            "${phoenix-histogram-pthread-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-pthread-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-pthread-glibc-bin
      "${dynamic-glibc-pthread-phoenix-root}/bin/kmeans-pthread-v2")
  set(phoenix-kmeans-pthread-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-pthread-glibc.dynamic.json")
  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-pthread-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pthread-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"2380541bb7b4836088c7b536e68c9109b5216405f50172659cf3785ee29018be\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_test(
    NAME "phoenix-kmeans-pthread-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-kmeans-pthread-glibc-bin}" -c
            "${phoenix-kmeans-pthread-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-pthread-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-pthread-glibc-bin
      "${dynamic-glibc-pthread-phoenix-root}/bin/linear_regression-pthread-v2")
  set(phoenix-linear-regression-pthread-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-glibc-small.bin")
  set(phoenix-linear-regression-pthread-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-glibc.dynamic.json")
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "from pathlib import Path; Path(r'${phoenix-linear-regression-pthread-glibc-input}').write_bytes(bytes([1, 2, 2, 4, 3, 6, 4, 8]))")
  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-pthread-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pthread-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-pthread-glibc-input}\"],\n    \"expected_stdout_sha256\": \"dbecd56c39fd6c5a577c7988b0fc133e84d2ba945a88ca2fe9fd0410499aa74d\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_test(
    NAME "phoenix-linear-regression-pthread-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-pthread-glibc-bin}" -c
            "${phoenix-linear-regression-pthread-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-pthread-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-matrix-multiply-pthread-glibc-bin
      "${dynamic-glibc-pthread-phoenix-root}/bin/matrix_multiply-pthread-v2")
  set(phoenix-matrix-multiply-pthread-glibc-workdir
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-glibc-workdir")
  set(phoenix-matrix-multiply-pthread-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-glibc.dynamic.json")
  file(MAKE_DIRECTORY "${phoenix-matrix-multiply-pthread-glibc-workdir}")
  configure_file(
    "${CMAKE_SOURCE_DIR}/aarch64.exec.lds"
    "${phoenix-matrix-multiply-pthread-glibc-workdir}/aarch64.exec.lds"
    COPYONLY)
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "import pathlib; d = pathlib.Path(r'${phoenix-matrix-multiply-pthread-glibc-workdir}'); data = bytes(32 * 32 * 4); (d / 'matrix_file_A.txt').write_bytes(data); (d / 'matrix_file_B.txt').write_bytes(data)")
  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-pthread-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pthread-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"32\"],\n    \"expected_stdout_sha256\": \"f0b05f66263dd77dfeafbcf7ff7704c56c913e7eb730e44385f22b6b79cbe1b3\",\n    \"expected_stderr_sha256\": \"23aab5596dacb17bb8e82fa96b660b092e5739383bc8fcecd731db46448e2f71\"\n}\n")
  add_test(
    NAME "phoenix-matrix-multiply-pthread-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-pthread-glibc-bin}" -c
            "${phoenix-matrix-multiply-pthread-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-pthread-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY
                                    "${phoenix-matrix-multiply-pthread-glibc-workdir}")

  set(phoenix-pca-pthread-glibc-bin
      "${dynamic-glibc-pthread-phoenix-root}/bin/pca-pthread-v2")
  set(phoenix-pca-pthread-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-pthread-glibc.dynamic.json")
  file(
    GENERATE
    OUTPUT "${phoenix-pca-pthread-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pthread-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"a21aa5473551d2d8c2675b4d81a38ea270e19007e218c6487d90b0ae5b255dd1\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_test(
    NAME "phoenix-pca-pthread-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-pca-pthread-glibc-bin}" -c
            "${phoenix-pca-pthread-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-pthread-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-string-match-pthread-glibc-bin
      "${dynamic-glibc-pthread-phoenix-root}/bin/string_match-pthread-v2")
  set(phoenix-string-match-pthread-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-glibc-small.txt")
  set(phoenix-string-match-pthread-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-glibc.dynamic.json")
  file(
    GENERATE
    OUTPUT "${phoenix-string-match-pthread-glibc-input}"
    CONTENT "Helloworld\nhowareyou\nferrari\nwhotheman\n")
  file(
    GENERATE
    OUTPUT "${phoenix-string-match-pthread-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pthread-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-pthread-glibc-input}\"],\n    \"expected_stdout_sha256\": \"e08f600b364500045cec207460953500ae4063d16f9324ff55d86d946a4663a4\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_test(
    NAME "phoenix-string-match-pthread-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-pthread-glibc-bin}" -c
            "${phoenix-string-match-pthread-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-pthread-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-word-count-pthread-glibc-bin
      "${dynamic-glibc-pthread-phoenix-root}/bin/word_count-pthread-v2")
  set(phoenix-word-count-pthread-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-glibc-small.txt")
  set(phoenix-word-count-pthread-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-glibc.dynamic.json")
  file(
    GENERATE
    OUTPUT "${phoenix-word-count-pthread-glibc-input}"
    CONTENT "alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha\nbeta beta beta beta beta beta beta beta beta beta beta\ngamma gamma gamma gamma gamma gamma gamma gamma gamma gamma\ndelta delta delta delta delta delta delta delta delta\nepsilon epsilon epsilon epsilon epsilon epsilon epsilon epsilon\nzeta zeta zeta zeta zeta zeta zeta\neta eta eta eta eta eta\ntheta theta theta theta theta\niota iota iota iota\nkappa kappa kappa\nlambda lambda\nmu\n")
  file(
    GENERATE
    OUTPUT "${phoenix-word-count-pthread-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pthread-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-pthread-glibc-input}\"],\n    \"expected_stdout_sha256\": \"08f9cb4ae364132df81fc14b8a95bd75358f048e860915d6f7c66fa453e046bd\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  add_test(
    NAME "phoenix-word-count-pthread-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-pthread-glibc-bin}" -c
            "${phoenix-word-count-pthread-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-pthread-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
endif()

if(dynamic-musl-pthread-phoenix-root)
  set(phoenix-histogram-pthread-musl-bin
      "${dynamic-musl-pthread-phoenix-root}/bin/histogram-pthread-v2")
  set(phoenix-histogram-pthread-musl-input
      "${dynamic-musl-pthread-phoenix-root}/data/histogram_datafiles/small.bmp")
  set(phoenix-histogram-pthread-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-pthread-musl.nlib")
  set(phoenix-histogram-pthread-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-pthread-musl.dynamic.json")

  file(
    WRITE "${phoenix-histogram-pthread-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b);\n"
    "i32 puts(ptr s);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "ptr malloc(u64 size);\n"
    "ptr calloc(u64 nmemb, u64 size);\n"
    "void free(ptr p);\n"
    "i32 sched_getaffinity(i32 pid, u64 cpusetsize, ptr mask);\n"
    "i64 sysconf(i32 name);\n"
    "i32 pthread_attr_init(ptr attr);\n"
    "i32 pthread_attr_setscope(ptr attr, i32 scope);\n"
    "i32 pthread_create(ptr thread, ptr attr, ptr start_routine, ptr arg);\n"
    "i32 pthread_join(u64 thread, ptr retval);\n"
    "i32 pthread_attr_destroy(ptr attr);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-histogram-pthread-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-histogram-pthread-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-pthread-musl-input}\"],\n    \"expected_stdout_sha256\": \"0612ff0e799fa2c008311341ef5afa93242089db8c5fa2eb1a5373697d65212d\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-histogram-pthread-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-histogram-pthread-musl-bin}" -c
            "${phoenix-histogram-pthread-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-pthread-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-pthread-musl-bin
      "${dynamic-musl-pthread-phoenix-root}/bin/kmeans-pthread-v2")
  set(phoenix-kmeans-pthread-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-pthread-musl.nlib")
  set(phoenix-kmeans-pthread-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-pthread-musl.dynamic.json")

  file(
    WRITE "${phoenix-kmeans-pthread-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "void free(ptr p);\n"
    "ptr malloc(u64 size);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i32 atoi(ptr nptr);\n"
    "i32 getopt(i32 argc, ptr argv, ptr optstring);\n"
    "ptr memset(ptr s, i32 c, u64 n);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "i32 rand();\n"
    "i32 sched_getaffinity(i32 pid, u64 cpusetsize, ptr mask);\n"
    "i64 sysconf(i32 name);\n"
    "i32 pthread_attr_init(ptr attr);\n"
    "i32 pthread_attr_setscope(ptr attr, i32 scope);\n"
    "i32 pthread_create(ptr thread, ptr attr, ptr start_routine, ptr arg);\n"
    "i32 pthread_join(u64 thread, ptr retval);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-pthread-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-kmeans-pthread-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"2380541bb7b4836088c7b536e68c9109b5216405f50172659cf3785ee29018be\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-kmeans-pthread-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-kmeans-pthread-musl-bin}" -c
            "${phoenix-kmeans-pthread-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-pthread-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-pthread-musl-bin
      "${dynamic-musl-pthread-phoenix-root}/bin/linear_regression-pthread-v2")
  # Use a tiny deterministic binary POINT_T input, matching the static pthread
  # regression style; the manifest's 50MB data is unnecessary for this check.
  set(phoenix-linear-regression-pthread-musl-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-musl-small.bin")
  set(phoenix-linear-regression-pthread-musl-cpu-stub-c
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-musl-cpu-stub.c")
  set(phoenix-linear-regression-pthread-musl-cpu-stub
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-musl-cpu-stub.o")
  set(phoenix-linear-regression-pthread-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-musl.nlib")
  set(phoenix-linear-regression-pthread-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-pthread-musl.dynamic.json")

  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "from pathlib import Path; Path(r'${phoenix-linear-regression-pthread-musl-input}').write_bytes(bytes([1, 2, 2, 4, 3, 6, 4, 8]))")
  file(
    WRITE "${phoenix-linear-regression-pthread-musl-cpu-stub-c}"
    "#define _GNU_SOURCE\n#include <sched.h>\n#include <stddef.h>\n#include <string.h>\n#include <unistd.h>\nint sched_getaffinity(pid_t pid, size_t cpusetsize, cpu_set_t *mask) { (void)pid; memset(mask, 0, cpusetsize); if (cpusetsize >= sizeof(unsigned long)) ((unsigned long *)mask)[0] = 1ul; return 0; }\nlong sysconf(int name) { (void)name; return 1; }\n")
  execute_process(
    COMMAND "${CMAKE_C_COMPILER}" -c
            "${phoenix-linear-regression-pthread-musl-cpu-stub-c}" -o
            "${phoenix-linear-regression-pthread-musl-cpu-stub}")

  file(
    WRITE "${phoenix-linear-regression-pthread-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 puts(ptr s);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "ptr calloc(u64 nmemb, u64 size);\n"
    "void free(ptr p);\n"
    "library \"${phoenix-linear-regression-pthread-musl-cpu-stub}\";\n"
    "i32 sched_getaffinity(i32 pid, u64 cpusetsize, ptr mask);\n"
    "i64 sysconf(i32 name);\n"
    "i32 pthread_attr_init(ptr attr);\n"
    "i32 pthread_attr_setscope(ptr attr, i32 scope);\n"
    "i32 pthread_create(ptr thread, ptr attr, ptr start_routine, ptr arg);\n"
    "i32 pthread_join(u64 thread, ptr retval);\n"
    "i32 pthread_attr_destroy(ptr attr);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-pthread-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-linear-regression-pthread-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-pthread-musl-input}\"],\n    \"expected_stdout_sha256\": \"dbecd56c39fd6c5a577c7988b0fc133e84d2ba945a88ca2fe9fd0410499aa74d\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-linear-regression-pthread-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-pthread-musl-bin}" -c
            "${phoenix-linear-regression-pthread-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-pthread-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-matrix-multiply-pthread-musl-bin
      "${dynamic-musl-pthread-phoenix-root}/bin/matrix_multiply-pthread-v2")
  set(phoenix-matrix-multiply-pthread-musl-workdir
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-musl-workdir")
  set(phoenix-matrix-multiply-pthread-musl-cpu-stub-c
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-musl-cpu-stub.c")
  set(phoenix-matrix-multiply-pthread-musl-cpu-stub
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-musl-cpu-stub.o")
  set(phoenix-matrix-multiply-pthread-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-musl.nlib")
  set(phoenix-matrix-multiply-pthread-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-pthread-musl.dynamic.json")

  file(MAKE_DIRECTORY "${phoenix-matrix-multiply-pthread-musl-workdir}")
  configure_file(
    "${CMAKE_SOURCE_DIR}/aarch64.exec.lds"
    "${phoenix-matrix-multiply-pthread-musl-workdir}/aarch64.exec.lds"
    COPYONLY)
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "import pathlib; d = pathlib.Path(r'${phoenix-matrix-multiply-pthread-musl-workdir}'); data = bytes(32 * 32 * 4); (d / 'matrix_file_A.txt').write_bytes(data); (d / 'matrix_file_B.txt').write_bytes(data)")
  file(
    WRITE "${phoenix-matrix-multiply-pthread-musl-cpu-stub-c}"
    "#define _GNU_SOURCE\n#include <sched.h>\n#include <stddef.h>\n#include <string.h>\n#include <sys/time.h>\n#include <unistd.h>\nint sched_getaffinity(pid_t pid, size_t cpusetsize, cpu_set_t *mask) { (void)pid; memset(mask, 0, cpusetsize); if (cpusetsize >= sizeof(unsigned long)) ((unsigned long *)mask)[0] = 1ul; return 0; }\nlong sysconf(int name) { (void)name; return 1; }\nint gettimeofday(struct timeval *tv, void *tz) { (void)tz; if (tv) { tv->tv_sec = 0; tv->tv_usec = 0; } return 0; }\n")
  execute_process(
    COMMAND "${CMAKE_C_COMPILER}" -c
            "${phoenix-matrix-multiply-pthread-musl-cpu-stub-c}" -o
            "${phoenix-matrix-multiply-pthread-musl-cpu-stub}")

  file(
    WRITE "${phoenix-matrix-multiply-pthread-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i64 write(i32 filedesc, ptr buf, u64 count);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 puts(ptr s);\n"
    "i32 fflush(ptr stream);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i32 atoi(ptr nptr);\n"
    "ptr memcpy(ptr dest, ptr src, u64 n);\n"
    "ptr memset(ptr s, i32 c, u64 n);\n"
    "void srand(u32 seed);\n"
    "i32 rand();\n"
    "i64 time(ptr tloc);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "ptr malloc(u64 size);\n"
    "void free(ptr p);\n"
    "library \"${phoenix-matrix-multiply-pthread-musl-cpu-stub}\";\n"
    "i32 sched_getaffinity(i32 pid, u64 cpusetsize, ptr mask);\n"
    "i64 sysconf(i32 name);\n"
    "i32 gettimeofday(ptr tv, ptr tz);\n"
    "i32 pthread_attr_init(ptr attr);\n"
    "i32 pthread_attr_setscope(ptr attr, i32 scope);\n"
    "i32 pthread_create(ptr thread, ptr attr, ptr start_routine, ptr arg);\n"
    "i32 pthread_join(u64 thread, ptr retval);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-pthread-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-matrix-multiply-pthread-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"32\"],\n    \"expected_stdout_sha256\": \"f0b05f66263dd77dfeafbcf7ff7704c56c913e7eb730e44385f22b6b79cbe1b3\",\n    \"expected_stderr_sha256\": \"23aab5596dacb17bb8e82fa96b660b092e5739383bc8fcecd731db46448e2f71\"\n}\n")

  add_test(
    NAME "phoenix-matrix-multiply-pthread-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-pthread-musl-bin}" -c
            "${phoenix-matrix-multiply-pthread-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-pthread-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY
                                    "${phoenix-matrix-multiply-pthread-musl-workdir}")

  set(phoenix-pca-pthread-musl-bin
      "${dynamic-musl-pthread-phoenix-root}/bin/pca-pthread-v2")
  set(phoenix-pca-pthread-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-pthread-musl.nlib")
  set(phoenix-pca-pthread-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-pthread-musl.dynamic.json")

  file(
    WRITE "${phoenix-pca-pthread-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "ptr malloc(u64 size);\n"
    "void free(ptr p);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "i32 atoi(ptr nptr);\n"
    "i32 getopt(i32 argc, ptr argv, ptr optstring);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "i32 rand();\n"
    "i32 sched_getaffinity(i32 pid, u64 cpusetsize, ptr mask);\n"
    "i64 sysconf(i32 name);\n"
    "i32 pthread_attr_init(ptr attr);\n"
    "i32 pthread_attr_setscope(ptr attr, i32 scope);\n"
    "i32 pthread_create(ptr thread, ptr attr, ptr start_routine, ptr arg);\n"
    "i32 pthread_join(u64 thread, ptr retval);\n"
    "i32 pthread_mutex_init(ptr mutex, ptr attr);\n"
    "i32 pthread_mutex_lock(ptr mutex);\n"
    "i32 pthread_mutex_unlock(ptr mutex);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-pca-pthread-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pca-pthread-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"deb79f46e45c17a2946468ba93c4fa8ce7bcf202019ef6bc359001c8e3c37da5\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-pca-pthread-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-pca-pthread-musl-bin}" -c
            "${phoenix-pca-pthread-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-pthread-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-string-match-pthread-musl-bin
      "${dynamic-musl-pthread-phoenix-root}/bin/string_match-pthread-v2")
  # Match the static pthread regression input; the manifest's 50MB input makes
  # elapsed-time stdout slow and less useful for this targeted dynamic check.
  set(phoenix-string-match-pthread-musl-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-musl-small.txt")
  set(phoenix-string-match-pthread-musl-cpu-stub-c
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-musl-cpu-stub.c")
  set(phoenix-string-match-pthread-musl-cpu-stub
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-musl-cpu-stub.o")
  set(phoenix-string-match-pthread-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-musl.nlib")
  set(phoenix-string-match-pthread-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-pthread-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-pthread-musl-input}"
    CONTENT "Helloworld\nhowareyou\nferrari\nwhotheman\n")
  file(
    WRITE "${phoenix-string-match-pthread-musl-cpu-stub-c}"
    "#define _GNU_SOURCE\n#include <sched.h>\n#include <stddef.h>\n#include <string.h>\n#include <sys/time.h>\n#include <unistd.h>\nint sched_getaffinity(pid_t pid, size_t cpusetsize, cpu_set_t *mask) { (void)pid; memset(mask, 0, cpusetsize); if (cpusetsize >= sizeof(unsigned long)) ((unsigned long *)mask)[0] = 1ul; return 0; }\nlong sysconf(int name) { (void)name; return 1; }\nint gettimeofday(struct timeval *tv, void *tz) { (void)tz; if (tv) { tv->tv_sec = 0; tv->tv_usec = 0; } return 0; }\n")
  execute_process(
    COMMAND "${CMAKE_C_COMPILER}" -c
            "${phoenix-string-match-pthread-musl-cpu-stub-c}" -o
            "${phoenix-string-match-pthread-musl-cpu-stub}")

  file(
    WRITE "${phoenix-string-match-pthread-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b);\n"
    "i32 puts(ptr s);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "void free(ptr p);\n"
    "ptr malloc(u64 size);\n"
    "ptr calloc(u64 nmemb, u64 size);\n"
    "i32 strcmp(ptr s1, ptr s2);\n"
    "u64 strlen(ptr s);\n"
    "void bzero(ptr s, u64 n);\n"
    "void srand(u32 seed);\n"
    "i64 time(ptr tloc);\n"
    "library \"${phoenix-string-match-pthread-musl-cpu-stub}\";\n"
    "i32 sched_getaffinity(i32 pid, u64 cpusetsize, ptr mask);\n"
    "i64 sysconf(i32 name);\n"
    "i32 gettimeofday(ptr tv, ptr tz);\n"
    "i32 pthread_attr_init(ptr attr);\n"
    "i32 pthread_attr_setscope(ptr attr, i32 scope);\n"
    "i32 pthread_create(ptr thread, ptr attr, ptr start_routine, ptr arg);\n"
    "i32 pthread_join(u64 thread, ptr retval);\n"
    "i32 pthread_attr_destroy(ptr attr);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-pthread-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-string-match-pthread-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-pthread-musl-input}\"],\n    \"expected_stdout_sha256\": \"e08f600b364500045cec207460953500ae4063d16f9324ff55d86d946a4663a4\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-string-match-pthread-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-pthread-musl-bin}" -c
            "${phoenix-string-match-pthread-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-pthread-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-word-count-pthread-musl-bin
      "${dynamic-musl-pthread-phoenix-root}/bin/word_count-pthread-v2")
  # Match the static pthread regression input; the manifest's 10MB input makes
  # elapsed-time stdout slow and less useful for this targeted dynamic check.
  set(phoenix-word-count-pthread-musl-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-musl-small.txt")
  set(phoenix-word-count-pthread-musl-time-stub-c
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-musl-time-stub.c")
  set(phoenix-word-count-pthread-musl-time-stub
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-musl-time-stub.o")
  set(phoenix-word-count-pthread-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-musl.nlib")
  set(phoenix-word-count-pthread-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-pthread-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-pthread-musl-input}"
    CONTENT "alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha\nbeta beta beta beta beta beta beta beta beta beta beta\ngamma gamma gamma gamma gamma gamma gamma gamma gamma gamma\ndelta delta delta delta delta delta delta delta delta\nepsilon epsilon epsilon epsilon epsilon epsilon epsilon epsilon\nzeta zeta zeta zeta zeta zeta zeta\neta eta eta eta eta eta\ntheta theta theta theta theta\niota iota iota iota\nkappa kappa kappa\nlambda lambda\nmu\n")
  file(
    WRITE "${phoenix-word-count-pthread-musl-time-stub-c}"
    "#define _GNU_SOURCE\n#include <sched.h>\n#include <stddef.h>\n#include <string.h>\n#include <sys/time.h>\n#include <unistd.h>\nint sched_getaffinity(pid_t pid, size_t cpusetsize, cpu_set_t *mask) { (void)pid; memset(mask, 0, cpusetsize); if (cpusetsize >= sizeof(unsigned long)) ((unsigned long *)mask)[0] = 1ul; return 0; }\nlong sysconf(int name) { (void)name; return 1; }\nint gettimeofday(struct timeval *tv, void *tz) { (void)tz; if (tv) { tv->tv_sec = 0; tv->tv_usec = 0; } return 0; }\n")
  execute_process(
    COMMAND "${CMAKE_C_COMPILER}" -c
            "${phoenix-word-count-pthread-musl-time-stub-c}" -o
            "${phoenix-word-count-pthread-musl-time-stub}")

  file(
    WRITE "${phoenix-word-count-pthread-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "void free(ptr p);\n"
    "ptr malloc(u64 size);\n"
    "ptr realloc(ptr p, u64 size);\n"
    "ptr memcpy(ptr dest, ptr src, u64 n);\n"
    "ptr memmove(ptr dest, ptr src, u64 n);\n"
    "i32 strcmp(ptr a, ptr b);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 atoi(ptr nptr);\n"
    "i32 toupper(i32 c);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "void qsort(ptr base, u64 nmemb, u64 size, ptr compar);\n"
    "i32 sched_getaffinity(i32 pid, u64 cpusetsize, ptr mask);\n"
    "i64 sysconf(i32 name);\n"
    "library \"${phoenix-word-count-pthread-musl-time-stub}\";\n"
    "i32 gettimeofday(ptr tv, ptr tz);\n"
    "i32 pthread_attr_init(ptr attr);\n"
    "i32 pthread_attr_setscope(ptr attr, i32 scope);\n"
    "i32 pthread_create(ptr thread, ptr attr, ptr start_routine, ptr arg);\n"
    "i32 pthread_join(u64 thread, ptr retval);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-pthread-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-word-count-pthread-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_GUEST_CPUS\": \"1\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-pthread-musl-input}\"],\n    \"expected_stdout_sha256\": \"08f9cb4ae364132df81fc14b8a95bd75358f048e860915d6f7c66fa453e046bd\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-word-count-pthread-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-pthread-musl-bin}" -c
            "${phoenix-word-count-pthread-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-pthread-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
endif()

if(dynamic-musl-phoenix-root)
  set(phoenix-histogram-musl-bin
      "${dynamic-musl-phoenix-root}/bin/histogram-seq-v2")
  set(phoenix-histogram-musl-input
      "${dynamic-musl-phoenix-root}/data/histogram_datafiles/small.bmp")
  set(phoenix-histogram-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-musl.nlib")
  set(phoenix-histogram-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-seq-musl.dynamic.json")
  set(phoenix-histogram-musl-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-seq-musl.hybrid.json")

  file(
    WRITE "${phoenix-histogram-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b);\n"
    "i32 puts(ptr s);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-histogram-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-histogram-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-musl-input}\"],\n    \"expected_stdout_sha256\": \"4b02b4c41e249a40a2acf92fd2bb32617318833b766d143d0cf135dc850b4deb\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-histogram-musl-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-histogram-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-musl-input}\"],\n    \"expected_stdout_sha256\": \"4b02b4c41e249a40a2acf92fd2bb32617318833b766d143d0cf135dc850b4deb\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-histogram-seq-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-histogram-musl-bin}" -c
            "${phoenix-histogram-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-seq-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-histogram-seq-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-histogram-musl-bin}" -c
            "${phoenix-histogram-musl-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-seq-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-musl-bin "${dynamic-musl-phoenix-root}/bin/kmeans-seq-v2")
  set(phoenix-kmeans-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-musl.nlib")
  set(phoenix-kmeans-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-seq-musl.dynamic.json")
  set(phoenix-kmeans-musl-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-seq-musl.hybrid.json")

  file(
    WRITE "${phoenix-kmeans-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "void free(ptr p);\n"
    "ptr malloc(u64 size);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i32 atoi(ptr nptr);\n"
    "i32 getopt(i32 argc, ptr argv, ptr optstring);\n"
    "ptr memset(ptr s, i32 c, u64 n);\n"
    "void exit(i32 status);\n"
    "i32 rand();\n")

  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-kmeans-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"7cfea4ec0cf21cf6b18ec16c83c757fc6922309d6a8377c4d896e0ff41ec0b1a\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-musl-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-kmeans-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"7cfea4ec0cf21cf6b18ec16c83c757fc6922309d6a8377c4d896e0ff41ec0b1a\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-kmeans-seq-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-kmeans-musl-bin}" -c
            "${phoenix-kmeans-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-seq-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-kmeans-seq-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-kmeans-musl-bin}" -c
            "${phoenix-kmeans-musl-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-seq-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-musl-bin
      "${dynamic-musl-phoenix-root}/bin/linear_regression-seq-v2")
  set(phoenix-linear-regression-musl-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-musl-small.txt")
  set(phoenix-linear-regression-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-musl.nlib")
  set(phoenix-linear-regression-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-seq-musl.dynamic.json")
  set(phoenix-linear-regression-musl-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-seq-musl.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-musl-input}"
    CONTENT "1 2\n2 4\n3 6\n4 8\n")

  file(
    WRITE "${phoenix-linear-regression-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 puts(ptr s);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-linear-regression-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-musl-input}\"],\n    \"expected_stdout_sha256\": \"1b6c00d9792bd06509c871002938a5dbd9684128304883fa34e9c980237bc915\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-musl-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-linear-regression-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-musl-input}\"],\n    \"expected_stdout_sha256\": \"1b6c00d9792bd06509c871002938a5dbd9684128304883fa34e9c980237bc915\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-linear-regression-seq-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-musl-bin}" -c
            "${phoenix-linear-regression-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-seq-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-linear-regression-seq-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-musl-bin}" -c
            "${phoenix-linear-regression-musl-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-seq-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-matrix-multiply-musl-bin
      "${dynamic-musl-phoenix-root}/bin/matrix_multiply-seq-v2")
  set(phoenix-matrix-multiply-musl-workdir
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-musl-workdir")
  set(phoenix-matrix-multiply-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-musl.nlib")
  set(phoenix-matrix-multiply-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-seq-musl.dynamic.json")
  set(phoenix-matrix-multiply-musl-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-seq-musl.hybrid.json")

  file(MAKE_DIRECTORY "${phoenix-matrix-multiply-musl-workdir}")
  configure_file("${CMAKE_SOURCE_DIR}/aarch64.exec.lds"
                 "${phoenix-matrix-multiply-musl-workdir}/aarch64.exec.lds" COPYONLY)
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "import pathlib, struct; d = pathlib.Path(r'${phoenix-matrix-multiply-musl-workdir}'); (d / 'matrix_file_A.txt').write_bytes(struct.pack('<4i', 1, 2, 3, 4)); (d / 'matrix_file_B.txt').write_bytes(struct.pack('<4i', 5, 6, 7, 8))")

  file(
    WRITE "${phoenix-matrix-multiply-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "i32 ftruncate(i32 filedesc, i64 length);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 puts(ptr s);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i32 atoi(ptr nptr);\n"
    "ptr memset(ptr s, i32 c, u64 n);\n"
    "void srand(u32 seed);\n"
    "i64 time(ptr tloc);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-matrix-multiply-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"2\"],\n    \"expected_stdout_sha256\": \"cda1ae0002bb95b50ac96c14369a3161858a2e53a5fd24f28769be9fbeb74a8b\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-musl-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-matrix-multiply-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"2\"],\n    \"expected_stdout_sha256\": \"cda1ae0002bb95b50ac96c14369a3161858a2e53a5fd24f28769be9fbeb74a8b\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-matrix-multiply-seq-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-musl-bin}" -c
            "${phoenix-matrix-multiply-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-seq-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${phoenix-matrix-multiply-musl-workdir}")

  add_test(
    NAME "phoenix-matrix-multiply-seq-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-musl-bin}" -c
            "${phoenix-matrix-multiply-musl-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-seq-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${phoenix-matrix-multiply-musl-workdir}")

  set(phoenix-string-match-musl-bin
      "${dynamic-musl-phoenix-root}/bin/string_match-seq-v2")
  set(phoenix-string-match-musl-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-musl-small.txt")
  set(phoenix-string-match-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-musl.nlib")
  set(phoenix-string-match-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-seq-musl.dynamic.json")
  set(phoenix-string-match-musl-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-seq-musl.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-musl-input}"
    CONTENT "abc\ndef\nfoo\nbar\n")

  file(
    WRITE "${phoenix-string-match-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b);\n"
    "i32 puts(ptr s);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "void free(ptr p);\n"
    "ptr malloc(u64 size);\n"
    "ptr calloc(u64 nmemb, u64 size);\n"
    "i32 strcmp(ptr s1, ptr s2);\n"
    "u64 strlen(ptr s);\n"
    "void bzero(ptr s, u64 n);\n"
    "i32 gettimeofday(ptr tv, ptr tz);\n"
    "void srand(u32 seed);\n"
    "i64 time(ptr tloc);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-string-match-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-musl-input}\"],\n    \"expected_stdout_sha256\": \"d3e6d6d2b99677ad4b816a27cec01ee4c604ffc70d3d8c504948201bc8270599\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-string-match-musl-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-string-match-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-musl-input}\"],\n    \"expected_stdout_sha256\": \"d3e6d6d2b99677ad4b816a27cec01ee4c604ffc70d3d8c504948201bc8270599\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-string-match-seq-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-musl-bin}" -c
            "${phoenix-string-match-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-seq-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-string-match-seq-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-musl-bin}" -c
            "${phoenix-string-match-musl-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-seq-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-word-count-musl-bin
      "${dynamic-musl-phoenix-root}/bin/word_count-seq-v2")
  set(phoenix-word-count-musl-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-musl-small.txt")
  set(phoenix-word-count-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-musl.nlib")
  set(phoenix-word-count-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-seq-musl.dynamic.json")
  set(phoenix-word-count-musl-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-seq-musl.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-musl-input}"
    CONTENT "apple banana apple cherry banana date\n")

  file(
    WRITE "${phoenix-word-count-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "void free(ptr p);\n"
    "ptr malloc(u64 size);\n"
    "ptr calloc(u64 nmemb, u64 size);\n"
    "ptr realloc(ptr p, u64 size);\n"
    "ptr memmove(ptr dest, ptr src, u64 n);\n"
    "i32 strcmp(ptr a, ptr b);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 atoi(ptr nptr);\n"
    "i32 toupper(i32 c);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "void qsort(ptr base, u64 nmemb, u64 size, ptr compar);\n")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-word-count-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-musl-input}\"],\n    \"expected_stdout_sha256\": \"eb28dcfcae8b1cc370c392809ed8bfc5e130724ec74c9a407545582bf282d5be\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-word-count-musl-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-word-count-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-musl-input}\"],\n    \"expected_stdout_sha256\": \"eb28dcfcae8b1cc370c392809ed8bfc5e130724ec74c9a407545582bf282d5be\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-word-count-seq-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-musl-bin}" -c
            "${phoenix-word-count-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-seq-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-word-count-seq-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-musl-bin}" -c
            "${phoenix-word-count-musl-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-seq-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-pca-musl-bin "${dynamic-musl-phoenix-root}/bin/pca-seq-v2")
  set(phoenix-pca-musl-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-musl.nlib")
  set(phoenix-pca-musl-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-seq-musl.dynamic.json")
  set(phoenix-pca-musl-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-seq-musl.hybrid.json")

  file(
    WRITE "${phoenix-pca-musl-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "ptr malloc(u64 size);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "i32 atoi(ptr nptr);\n"
    "i32 getopt(i32 argc, ptr argv, ptr optstring);\n"
    "void exit(i32 status);\n"
    "i32 rand();\n")

  file(
    GENERATE
    OUTPUT "${phoenix-pca-musl-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pca-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"7baffcc94b0b5de6cf8e4e60d84e7fddf9464767071869434d8524065a04ae87\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-pca-musl-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-pca-musl-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"1\"],\n    \"expected_stdout_sha256\": \"cfef00e885337ad5b5c3be804439d43c0baabbcce03f0b7ec3a0b9e2e743bd40\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-pca-seq-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-pca-musl-bin}"
            -c "${phoenix-pca-musl-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-seq-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-pca-seq-musl:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-pca-musl-bin}"
            -c "${phoenix-pca-musl-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-seq-musl:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
endif()

if(dynamic-phoenix-root)
  set(phoenix-histogram-glibc-bin
      "${dynamic-phoenix-root}/bin/histogram-seq-v2")
  set(phoenix-histogram-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-4x1.bmp")
  set(phoenix-histogram-glibc-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-glibc.nlib")
  set(phoenix-histogram-glibc-gmon-stub-c
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-glibc-gmon-stub.c")
  set(phoenix-histogram-glibc-gmon-stub
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-glibc-gmon-stub.o")
  set(phoenix-histogram-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-seq-glibc.dynamic.json")
  set(phoenix-histogram-glibc-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-histogram-seq-glibc.hybrid.json")

  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "import pathlib, struct; p=pathlib.Path(r'${phoenix-histogram-glibc-input}'); w,h=4,1; pixels=bytes([0,0,255,0,255,0,255,0,0,255,255,255]); size=54+len(pixels); p.write_bytes(b'BM'+struct.pack('<IHHI',size,0,0,54)+struct.pack('<IiiHHIIiiII',40,w,h,1,24,0,len(pixels),2835,2835,0,0)+pixels)")

  file(WRITE "${phoenix-histogram-glibc-gmon-stub-c}"
       "void __gmon_start__(void) {}\n")
  execute_process(
    COMMAND "${CMAKE_C_COMPILER}" -c "${phoenix-histogram-glibc-gmon-stub-c}"
            -o "${phoenix-histogram-glibc-gmon-stub}")

  file(
    WRITE "${phoenix-histogram-glibc-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b);\n"
    "i32 puts(ptr s);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "library \"${phoenix-histogram-glibc-gmon-stub}\";\n"
    "void __gmon_start__();\n")

  file(
    GENERATE
    OUTPUT "${phoenix-histogram-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-histogram-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-glibc-input}\"],\n    \"expected_stdout_sha256\": \"f38892657ac7870e861b311ce895b102943687eca207bb27fba9c9353477c088\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-histogram-glibc-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-histogram-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-glibc-input}\"],\n    \"expected_stdout_sha256\": \"f38892657ac7870e861b311ce895b102943687eca207bb27fba9c9353477c088\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-histogram-seq-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-histogram-glibc-bin}" -c
            "${phoenix-histogram-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-seq-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-histogram-seq-glibc:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-histogram-glibc-bin}" -c
            "${phoenix-histogram-glibc-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-seq-glibc:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-glibc-bin "${dynamic-phoenix-root}/bin/kmeans-seq-v2")
  set(phoenix-kmeans-glibc-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-glibc.nlib")
  set(phoenix-kmeans-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-seq-glibc.dynamic.json")
  set(phoenix-kmeans-glibc-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-seq-glibc.hybrid.json")

  file(
    WRITE "${phoenix-kmeans-glibc-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "void free(ptr p);\n"
    "ptr malloc(u64 size);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 __printf_chk(i32 flag, ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 __fprintf_chk(ptr stream, i32 flag, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i64 strtol(ptr nptr, ptr endptr, i32 base);\n"
    "i64 __isoc23_strtol(ptr nptr, ptr endptr, i32 base);\n"
    "i32 getopt(i32 argc, ptr argv, ptr optstring);\n"
    "ptr memset(ptr s, i32 c, u64 n);\n"
    "ptr __memset_chk(ptr s, i32 c, u64 n, u64 destlen);\n"
    "void exit(i32 status);\n"
    "i32 rand();\n"
    "library \"${phoenix-histogram-glibc-gmon-stub}\";\n"
    "void __gmon_start__();\n")

  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-kmeans-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"7cfea4ec0cf21cf6b18ec16c83c757fc6922309d6a8377c4d896e0ff41ec0b1a\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-glibc-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-kmeans-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"7cfea4ec0cf21cf6b18ec16c83c757fc6922309d6a8377c4d896e0ff41ec0b1a\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-kmeans-seq-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-kmeans-glibc-bin}" -c
            "${phoenix-kmeans-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-seq-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-kmeans-seq-glibc:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-kmeans-glibc-bin}" -c
            "${phoenix-kmeans-glibc-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-seq-glibc:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-glibc-bin
      "${dynamic-phoenix-root}/bin/linear_regression-seq-v2")
  set(phoenix-linear-regression-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-glibc-small.txt")
  set(phoenix-linear-regression-glibc-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-glibc.nlib")
  set(phoenix-linear-regression-glibc-hybrid-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-glibc.hybrid.nlib")
  set(phoenix-linear-regression-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-seq-glibc.dynamic.json")
  set(phoenix-linear-regression-glibc-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-seq-glibc.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-glibc-input}"
    CONTENT "1 2\n2 4\n3 6\n4 8\n")

  file(
    WRITE "${phoenix-linear-regression-glibc-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 puts(ptr s);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n")

  file(
    WRITE "${phoenix-linear-regression-glibc-hybrid-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 puts(ptr s);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "library \"${phoenix-histogram-glibc-gmon-stub}\";\n"
    "void __gmon_start__();\n")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-linear-regression-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-glibc-input}\"],\n    \"expected_stdout_sha256\": \"1b6c00d9792bd06509c871002938a5dbd9684128304883fa34e9c980237bc915\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-glibc-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-linear-regression-glibc-hybrid-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-glibc-input}\"],\n    \"expected_stdout_sha256\": \"1b6c00d9792bd06509c871002938a5dbd9684128304883fa34e9c980237bc915\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-linear-regression-seq-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-glibc-bin}" -c
            "${phoenix-linear-regression-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-seq-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-linear-regression-seq-glibc:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-glibc-bin}" -c
            "${phoenix-linear-regression-glibc-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-seq-glibc:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-matrix-multiply-glibc-bin
      "${dynamic-phoenix-root}/bin/matrix_multiply-seq-v2")
  set(phoenix-matrix-multiply-glibc-workdir
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-glibc-workdir")
  set(phoenix-matrix-multiply-glibc-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-glibc.nlib")
  set(phoenix-matrix-multiply-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-seq-glibc.dynamic.json")
  set(phoenix-matrix-multiply-glibc-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-seq-glibc.hybrid.json")

  file(MAKE_DIRECTORY "${phoenix-matrix-multiply-glibc-workdir}")
  configure_file("${CMAKE_SOURCE_DIR}/aarch64.exec.lds"
                 "${phoenix-matrix-multiply-glibc-workdir}/aarch64.exec.lds" COPYONLY)
  execute_process(
    COMMAND
      "${Python3_EXECUTABLE}" "-c"
      "import pathlib, struct; d = pathlib.Path(r'${phoenix-matrix-multiply-glibc-workdir}'); (d / 'matrix_file_A.txt').write_bytes(struct.pack('<4i', 1, 2, 3, 4)); (d / 'matrix_file_B.txt').write_bytes(struct.pack('<4i', 5, 6, 7, 8))")

  file(
    WRITE "${phoenix-matrix-multiply-glibc-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "i32 ftruncate(i32 filedesc, i64 length);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 puts(ptr s);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "u64 fwrite(ptr ptrarg, u64 size, u64 nmemb, ptr stream);\n"
    "i64 __isoc23_strtol(ptr nptr, ptr endptr, i32 base);\n"
    "ptr memset(ptr s, i32 c, u64 n);\n"
    "void srand(u32 seed);\n"
    "i64 time(ptr tloc);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "library \"${phoenix-histogram-glibc-gmon-stub}\";\n"
    "void __gmon_start__();\n")

  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-matrix-multiply-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"2\"],\n    \"expected_stdout_sha256\": \"cda1ae0002bb95b50ac96c14369a3161858a2e53a5fd24f28769be9fbeb74a8b\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-matrix-multiply-glibc-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-matrix-multiply-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"2\"],\n    \"expected_stdout_sha256\": \"cda1ae0002bb95b50ac96c14369a3161858a2e53a5fd24f28769be9fbeb74a8b\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-matrix-multiply-seq-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-glibc-bin}" -c
            "${phoenix-matrix-multiply-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-seq-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${phoenix-matrix-multiply-glibc-workdir}")

  add_test(
    NAME "phoenix-matrix-multiply-seq-glibc:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-glibc-bin}" -c
            "${phoenix-matrix-multiply-glibc-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-seq-glibc:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${phoenix-matrix-multiply-glibc-workdir}")

  set(phoenix-pca-glibc-bin "${dynamic-phoenix-root}/bin/pca-seq-v2")
  set(phoenix-pca-glibc-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-glibc.nlib")
  set(phoenix-pca-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-seq-glibc.dynamic.json")
  set(phoenix-pca-glibc-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-seq-glibc.hybrid.json")

  file(
    WRITE "${phoenix-pca-glibc-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "ptr malloc(u64 size);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 fputc(i32 c, ptr stream);\n"
    "i64 __isoc23_strtol(ptr nptr, ptr endptr, i32 base);\n"
    "i32 getopt(i32 argc, ptr argv, ptr optstring);\n"
    "void exit(i32 status);\n"
    "i32 rand();\n"
    "library \"${phoenix-histogram-glibc-gmon-stub}\";\n"
    "void __gmon_start__();\n")

  file(
    GENERATE
    OUTPUT "${phoenix-pca-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-pca-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"7baffcc94b0b5de6cf8e4e60d84e7fddf9464767071869434d8524065a04ae87\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-pca-glibc-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-pca-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"1\"],\n    \"expected_stdout_sha256\": \"cfef00e885337ad5b5c3be804439d43c0baabbcce03f0b7ec3a0b9e2e743bd40\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-pca-seq-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-pca-glibc-bin}" -c
            "${phoenix-pca-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-seq-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-pca-seq-glibc:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-pca-glibc-bin}" -c
            "${phoenix-pca-glibc-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-seq-glibc:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-string-match-glibc-bin
      "${dynamic-phoenix-root}/bin/string_match-seq-v2")
  set(phoenix-string-match-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-glibc-small.txt")
  set(phoenix-string-match-glibc-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-glibc.nlib")
  set(phoenix-string-match-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-seq-glibc.dynamic.json")
  set(phoenix-string-match-glibc-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-seq-glibc.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-glibc-input}"
    CONTENT "abc\ndef\nfoo\nbar\n")

  file(
    WRITE "${phoenix-string-match-glibc-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "void free(ptr p);\n"
    "ptr malloc(u64 size);\n"
    "ptr calloc(u64 nmemb, u64 size);\n"
    "i32 puts(ptr s);\n"
    "u64 strlen(ptr s);\n"
    "i32 strcmp(ptr a, ptr b);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i32 gettimeofday(ptr tv, ptr tz);\n"
    "void srand(u32 seed);\n"
    "i64 time(ptr tloc);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 __printf_chk(i32 flag, ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 __fprintf_chk(ptr stream, i32 flag, ptr fmt, u64 a, u64 b, u64 c);\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "void __stack_chk_fail();\n"
    "library \"${phoenix-histogram-glibc-gmon-stub}\";\n"
    "void __gmon_start__();\n")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-string-match-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-glibc-input}\"],\n    \"expected_stdout_sha256\": \"d3e6d6d2b99677ad4b816a27cec01ee4c604ffc70d3d8c504948201bc8270599\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-string-match-glibc-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-string-match-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-glibc-input}\"],\n    \"expected_stdout_sha256\": \"d3e6d6d2b99677ad4b816a27cec01ee4c604ffc70d3d8c504948201bc8270599\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-string-match-seq-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-glibc-bin}" -c
            "${phoenix-string-match-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-seq-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-string-match-seq-glibc:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-glibc-bin}" -c
            "${phoenix-string-match-glibc-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-seq-glibc:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-word-count-glibc-bin
      "${dynamic-phoenix-root}/bin/word_count-seq-v2")
  set(phoenix-word-count-glibc-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-glibc-small.txt")
  set(phoenix-word-count-glibc-nlib
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-glibc.nlib")
  set(phoenix-word-count-glibc-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-seq-glibc.dynamic.json")
  set(phoenix-word-count-glibc-hybrid-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-seq-glibc.hybrid.json")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-glibc-input}"
    CONTENT "apple banana apple cherry banana date\n")

  file(
    WRITE "${phoenix-word-count-glibc-nlib}"
    "void __libc_start_main(u64 main, u64 argc, ptr argv, u64 init, u64 fini, u64 rtldfini, u64 stackend);\n"
    "void free(ptr p);\n"
    "ptr malloc(u64 size);\n"
    "ptr calloc(u64 nmemb, u64 size);\n"
    "ptr realloc(ptr p, u64 size);\n"
    "ptr memmove(ptr dest, ptr src, u64 n);\n"
    "i32 strcmp(ptr a, ptr b);\n"
    "i32 puts(ptr s);\n"
    "i32 printf(ptr fmt, u64 a, u64 b, u64 c, u64 d);\n"
    "i32 fprintf(ptr stream, ptr fmt, u64 a, u64 b, u64 c);\n"
    "i32 open(ptr path, i32 flags, i32 mode);\n"
    "i32 fstat(i32 filedesc, ptr statbuf);\n"
    "ptr mmap(ptr addr, u64 length, i32 prot, i32 flags, i32 filedesc, i64 offset);\n"
    "i32 munmap(ptr addr, u64 length);\n"
    "i32 close(i32 filedesc);\n"
    "i64 __isoc23_strtol(ptr nptr, ptr endptr, i32 base);\n"
    "ptr __ctype_toupper_loc();\n"
    "void perror(ptr s);\n"
    "void exit(i32 status);\n"
    "void __assert_fail(ptr assertion, ptr file, u32 line, ptr function);\n"
    "void qsort(ptr base, u64 nmemb, u64 size, ptr compar);\n"
    "library \"${phoenix-histogram-glibc-gmon-stub}\";\n"
    "void __gmon_start__();\n")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-glibc-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--nlib\", \"${phoenix-word-count-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-glibc-input}\"],\n    \"expected_stdout_sha256\": \"eb28dcfcae8b1cc370c392809ed8bfc5e130724ec74c9a407545582bf282d5be\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")
  file(
    GENERATE
    OUTPUT "${phoenix-word-count-glibc-hybrid-config}"
    CONTENT "{\n    \"compile_flags\": [\"--nlib\", \"${phoenix-word-count-glibc-nlib}\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\",\n        \"ARANCINI_OPTIMIZE_FLAGS\": \"false\",\n        \"LD_LIBRARY_PATH\": \"$<TARGET_FILE_DIR:arancini-runtime>${host-libatomic-libdir}\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-glibc-input}\"],\n    \"expected_stdout_sha256\": \"eb28dcfcae8b1cc370c392809ed8bfc5e130724ec74c9a407545582bf282d5be\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-word-count-seq-glibc:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-glibc-bin}" -c
            "${phoenix-word-count-glibc-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-seq-glibc:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  add_test(
    NAME "phoenix-word-count-seq-glibc:hybrid"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-glibc-bin}" -c
            "${phoenix-word-count-glibc-hybrid-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-seq-glibc:hybrid"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")
endif()

# Option definitions
option(BUILD_KERNELS "Build test kernels" OFF)
option(BUILD_QSORT "Build qsort test object" OFF)
option(BUILD_COLLATZ "Build collatz test object" OFF)
option(BUILD_EXAMPLES "Build examples test objects" OFF)

# Build collatz
if(BUILD_COLLATZ)
  add_executable(indiv individual.S)
  target_link_options(indiv PUBLIC -nostdlib)
endif()

# Build qsort
if(BUILD_QSORT)
  add_subdirectory(qsort)
endif()

# Build examples
if(BUILD_EXAMPLES)
  add_subdirectory(examples)
endif()

# Build kernels
if(BUILD_KERNELS)
  add_subdirectory(kernels)
endif()

# Install static binaries
install(DIRECTORY hello-world DESTINATION ${CMAKE_INSTALL_PREFIX}/test)
install(DIRECTORY phoenix DESTINATION ${CMAKE_INSTALL_PREFIX}/test)
