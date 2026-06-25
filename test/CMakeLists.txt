cmake_minimum_required(VERSION 3.22)
project(arancini-tests LANGUAGES C ASM)

find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(tester "${Python3_EXECUTABLE}"
           "${CMAKE_CURRENT_LIST_DIR}/translate-and-run.py")

set(static-musl-phoenix-path
    "share/static-musl-phoenix"
    CACHE PATH "Path to static-musl-phoenix executables")
set(static-musl-phoenix-root
    ""
    CACHE PATH "Path to Phoenix x86_64 musl static package root (with bin/ and data/)")
set(dynamic-phoenix-root
    ""
    CACHE PATH "Path to dynamically linked Phoenix x86_64 package root (with bin/)")
set(dynamic-musl-phoenix-root
    ""
    CACHE PATH "Path to dynamically linked Phoenix x86_64 musl package root (with bin/ and data/)")
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
