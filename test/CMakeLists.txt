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

  file(
    GENERATE
    OUTPUT "${phoenix-histogram-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-histogram-input}\"],\n    \"expected_stdout_sha256\": \"4b02b4c41e249a40a2acf92fd2bb32617318833b766d143d0cf135dc850b4deb\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-histogram-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-histogram-bin}"
            -c "${phoenix-histogram-config}" --log-level INFO)
  set_tests_properties("phoenix-histogram-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-kmeans-bin "${static-musl-phoenix-root}/bin/kmeans-seq-static-musl")
  set(phoenix-kmeans-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-kmeans-seq-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-kmeans-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"-d\", \"3\", \"-c\", \"3\", \"-p\", \"1000\", \"-s\", \"1000\"],\n    \"expected_stdout_sha256\": \"2100bc36e823308a3f392e216fbdde94c79c012c0aa47a139c6b3afd66c39e7f\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-kmeans-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-kmeans-bin}" -c
            "${phoenix-kmeans-config}" --log-level INFO)
  set_tests_properties("phoenix-kmeans-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-linear-regression-bin
      "${static-musl-phoenix-root}/bin/linear_regression-seq-static-musl")
  set(phoenix-linear-regression-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-small.txt")
  set(phoenix-linear-regression-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-linear-regression-seq-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-input}"
    CONTENT "1 2\n2 4\n3 6\n4 8\n")

  file(
    GENERATE
    OUTPUT "${phoenix-linear-regression-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-linear-regression-input}\"],\n    \"expected_stdout_sha256\": \"9f369a68eb8d761dfe6d725c40323f40d89a0deb3d11c3d8259beb31f855a282\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-linear-regression-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-linear-regression-bin}" -c
            "${phoenix-linear-regression-config}" --log-level INFO)
  set_tests_properties("phoenix-linear-regression-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-matrix-multiply-bin
      "${static-musl-phoenix-root}/bin/matrix_multiply-seq-static-musl")
  set(phoenix-matrix-multiply-workdir
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-workdir")
  set(phoenix-matrix-multiply-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-matrix-multiply-seq-static-musl.dynamic.json")

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

  add_test(
    NAME "phoenix-matrix-multiply-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-matrix-multiply-bin}" -c
            "${phoenix-matrix-multiply-config}" --log-level INFO)
  set_tests_properties("phoenix-matrix-multiply-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${phoenix-matrix-multiply-workdir}")

  set(phoenix-string-match-bin
      "${static-musl-phoenix-root}/bin/string_match-seq-static-musl")
  set(phoenix-string-match-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-small.txt")
  set(phoenix-string-match-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-string-match-seq-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-input}"
    CONTENT "abc\ndef\nfoo\nbar\n")

  file(
    GENERATE
    OUTPUT "${phoenix-string-match-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-string-match-input}\"],\n    \"expected_stdout_sha256\": \"d3e6d6d2b99677ad4b816a27cec01ee4c604ffc70d3d8c504948201bc8270599\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-string-match-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-string-match-bin}" -c
            "${phoenix-string-match-config}" --log-level INFO)
  set_tests_properties("phoenix-string-match-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-word-count-bin
      "${static-musl-phoenix-root}/bin/word_count-seq-static-musl")
  set(phoenix-word-count-input
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-small.txt")
  set(phoenix-word-count-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-word-count-seq-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-input}"
    CONTENT "apple banana apple cherry banana date\n")

  file(
    GENERATE
    OUTPUT "${phoenix-word-count-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"${phoenix-word-count-input}\"],\n    \"expected_stdout_sha256\": \"eb28dcfcae8b1cc370c392809ed8bfc5e130724ec74c9a407545582bf282d5be\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-word-count-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i
            "${phoenix-word-count-bin}" -c
            "${phoenix-word-count-config}" --log-level INFO)
  set_tests_properties("phoenix-word-count-seq-static-musl:dynamic"
                       PROPERTIES TIMEOUT 180
                                  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}")

  set(phoenix-pca-bin "${static-musl-phoenix-root}/bin/pca-seq-static-musl")
  set(phoenix-pca-config
      "${CMAKE_CURRENT_BINARY_DIR}/phoenix-pca-seq-static-musl.dynamic.json")

  file(
    GENERATE
    OUTPUT "${phoenix-pca-config}"
    CONTENT "{\n    \"compile_flags\": [\"--no-static\", \"--cxx-compiler-path\", \"clang++\", \"--runtime-lib-path\", \"$<TARGET_FILE:arancini-runtime>\"],\n    \"runtime_environment\": {\n        \"ARANCINI_ENABLE_LOG\": \"false\"\n    },\n    \"runtime_flags\": [\"-r\", \"64\", \"-c\", \"64\", \"-s\", \"100\"],\n    \"expected_stdout_sha256\": \"bf18326b07306e4afbef0464192844e43b993f4e08d7e27cb120394943d7c8bc\",\n    \"expected_stderr_sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"\n}\n")

  add_test(
    NAME "phoenix-pca-seq-static-musl:dynamic"
    COMMAND ${tester} -t "$<TARGET_FILE:txlat>" -i "${phoenix-pca-bin}" -c
            "${phoenix-pca-config}" --log-level INFO)
  set_tests_properties("phoenix-pca-seq-static-musl:dynamic"
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
