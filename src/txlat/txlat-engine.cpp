#include <arancini/elf/elf-reader.h>
#include <arancini/input/x86/x86-input-arch.h>
#include <arancini/ir/chunk.h>
#include <arancini/ir/default-ir-builder.h>
#include <arancini/ir/dot-graph-generator.h>
#include <arancini/ir/opt.h>
#include <arancini/native_lib/native-lib.h>
#include <arancini/output/static/llvm/llvm-static-output-engine.h>
#include <arancini/output/static/static-output-engine.h>
#include <arancini/txlat/txlat-engine.h>
#include <arancini/util/logger.h>
#include <arancini/util/tempfile-manager.h>
#include <arancini/util/tempfile.h>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <optional>
#include <ostream>
#include <string>

using namespace arancini::txlat;
using namespace arancini::elf;
using namespace arancini::ir;
using namespace arancini::input;
using namespace arancini::input::x86;
using namespace arancini::output;
using namespace arancini::output::o_static::llvm;
using namespace arancini::util;
using namespace arancini::native_lib;

static std::set<std::string> allowed_symbols = {"cmpstr",
                                                "cmpnum",
                                                "swap",
                                                "_qsort",
                                                "_start",
                                                "test",
                                                "__libc_start_main",
                                                "_dl_aux_init",
                                                "__assert_fail",
                                                "__dcgettext",
                                                "__dcigettext"};

// Determine host architecture (with help from the build system)
// Needed to select the appropriate linker script
#ifdef DBT_ARCH_STR_LOWER
static std::string_view architecture{DBT_ARCH_STR_LOWER};
#else
#error "Cannot determine architecture"
#endif

void txlat_engine::process_options(
    arancini::output::o_static::static_output_engine &oe,
    const boost::program_options::variables_map &cmdline) {
    if (auto llvmoe = dynamic_cast<llvm_static_output_engine *>(&oe)) {
        llvmoe->set_debug(cmdline.count("debug"));
        if (cmdline.count("dump-llvm")) {
            auto filename = cmdline.at("dump-llvm");
            llvmoe->set_debug_dump_filename(filename.as<std::string>());
        }
        if (cmdline.count("llvm-codegen-nofence")) {
            llvmoe->set_codegen_fence(false);
        }
    }
}

static void run_or_fail(const std::string &cmd) {
    util::global_logger.info("Running: {}...\n", cmd);
    if (std::system(cmd.c_str()) != 0) {
        throw std::runtime_error("error whilst running subcommand");
    }
}

/*
  This function acts as the main driver for the binary translation.
  First it parses the ELF binary, lifting each section to the Arancini IR.
  Finally, the lifted IR is processed by the output engine.
  For example, the output engine can generate the target binary or a
  visualisation of the Arancini IR.
*/
void txlat_engine::translate(
    const boost::program_options::variables_map &cmdline) {
    // Create a manager for temporary files, as we'll be creating a series of
    // them.  When this object is destroyed, all temporary files are
    // automatically unlinked.
    tempfile_manager tf;

    std::optional<NativeLibs> nlibs;
    std::set<std::string> needed_nlibs;
#ifdef NLIB
    if (cmdline.count("nlib")) {
        const auto &filename = cmdline.at("nlib").as<std::string>();
        std::ifstream a(filename);
        nlibs.emplace(a);

        if (!nlibs->parse()) {
            ::util::global_logger.warn("Parsing nlib file {} failed.\n",
                                       filename);
            nlibs = std::nullopt;
        }
    }
#endif

    // Parse the input ELF file
    const auto &filename = cmdline.at("input").as<std::string>();
    elf_reader elf(filename);
    elf.parse();
    bool is_exec = elf.type() == elf::elf_type::exec;

    // TODO: Figure the input engine out from ELF architecture header
    auto das = cmdline.at("syntax").as<std::string>() == "att"
                   ? disassembly_syntax::att
                   : disassembly_syntax::intel;
    auto ia = std::make_unique<arancini::input::x86::x86_input_arch>(
        cmdline.count("debug") || cmdline.count("graph"), das);

    std::string prefix = "";
    if (cmdline.find("keep-objs") != cmdline.end()) {
        prefix = cmdline.at("keep-objs").as<std::string>();
    }
    // Construct the output engine
    auto intermediate_file = tf.create_file(prefix, ".o");
    auto oe = std::make_shared<
        arancini::output::o_static::llvm::llvm_static_output_engine>(
        intermediate_file->name(), is_exec);
    process_options(*oe, cmdline);

    oe->set_entrypoint(elf.get_entrypoint());

    std::shared_ptr<symbol_table> dyn_sym;
    std::shared_ptr<symbol_table> sym_t;
    std::shared_ptr<plt_table> plt_tab;
    std::vector<std::shared_ptr<rela_table>> relocations;
    std::vector<std::shared_ptr<relr_array>> relocations_r;
    std::set<symbol> unique_translated;
    std::map<std::string, uint64_t> native_symbol_addrs;
    // pairs of symbols and maximum size (aka. until the end of the section)
    std::vector<std::pair<symbol, size_t>> zero_size;

    // Loop over each symbol table, and translate the symbol.
    for (auto &s : elf.sections()) {
        if (s->type() == elf::section_type::progbits) {
            if (s->name() == ".plt") {
                auto st = std::static_pointer_cast<plt_table>(s);
                plt_tab = std::move(st);
            }
        } else if (s->type() == elf::section_type::dynamic_symbol_table) {
            auto st = std::static_pointer_cast<symbol_table>(s);
            dyn_sym = std::move(st);
#ifdef NLIB
            for (const auto &sym : dyn_sym->symbols()) {
                if (nlibs.has_value() && nlibs->native_functions().count(sym.name())) {
                    const nlib_function &func =
                        nlibs->native_functions().at(sym.name());
                    needed_nlibs.insert(func.libname);
                    oe->add_chunk(generate_wrapper(*ia, func));
                    // Reserve a synthetic guest PC for nlib functions. This lets
                    // dynamic relocations (GLOB_DAT/JUMP_SLOT) resolve to a value
                    // that the static/dynamic bridge can dispatch to the wrapper,
                    // even in --no-static mode where no PLT chunks are emitted.
                    native_symbol_addrs.emplace(sym.name(),
                                                0x700000000000ull +
                                                    native_symbol_addrs.size() * 0x10ull);
                }
            }
#endif
        } else if (s->type() == elf::section_type::relocation_addend) {
            auto st = std::static_pointer_cast<rela_table>(s);
            relocations.push_back(std::move(st));
        } else if (s->type() == elf::section_type::relr) {
            auto st = std::static_pointer_cast<relr_array>(s);
            relocations_r.push_back(std::move(st));
        } else if (s->type() == section_type::symbol_table) {
            auto st = std::static_pointer_cast<symbol_table>(s);
            if (!cmdline.count("no-static")) {
                auto syms = st->symbols();
                for (auto sym = syms.cbegin(); sym != syms.cend(); sym++) {
                    if (!sym->is_func())
                        continue;
                    ::util::global_logger.debug(
                        "PASS1: looking at symbol {} @ 0x{:#x}\n", sym->name(),
                        sym->value());
                    if (!sym->value())
                        continue;
#ifdef NLIB
                    if (nlibs.has_value() &&
                        nlibs->native_functions().count(sym->name())) {
                        const nlib_function &func =
                            nlibs->native_functions().at(sym->name());
                        needed_nlibs.insert(func.libname);
                        if (!native_symbol_addrs.count(sym->name())) {
                            oe->add_chunk(generate_wrapper(*ia, func));
                            native_symbol_addrs.emplace(sym->name(), sym->value());
                        }
                        oe->add_function_decl(
                            sym->value(),
                            "__arancini__" + sym->name() + "_wrapper");
                        continue;
                    }
#endif
                    if (!sym->size()) {
                        // get the section the symbol is in

                        auto sec = elf.get_section(sym->section_index());
                        size_t size =
                            sec->address() + sec->data_size() - sym->value();
                        zero_size.push_back({*sym, size});
                        unique_translated.insert(*sym);
                        continue;
                    }
                    unique_translated.insert(*sym);
                    oe->add_chunk(translate_symbol(*ia, elf, *sym));
                }
            }
            sym_t = std::move(st);
        }
    }

    // PASS2
    for (const auto &p : zero_size) {
        ::util::global_logger.debug("PASS2: doing (0 size), symbol {}\n",
                                    p.first.name());
        // find the address of the symbol after sym in the text section, and
        // assume that the size of sym is until there
        size_t size = p.second;
        auto next = std::next(unique_translated.find(p.first), 1);
        if (next != unique_translated.end()) {
            if (next->value() - p.first.value() < size)
                size = next->value() - p.first.value();
        }
        auto fixed_sym = symbol(p.first.name(), p.first.value(), size,
                                p.first.section_index(), p.first.info(), 0);

        oe->add_chunk(translate_symbol(*ia, elf, fixed_sym));
    }

    for (const auto &[name, addr] : native_symbol_addrs) {
        oe->add_function_decl(addr, "__arancini__" + name + "_wrapper");
    }
    if (nlibs.has_value() &&
        nlibs->native_functions().count("__libc_start_main")) {
        nlib_function ret{"__libc_start_main_return", "",
                          function_type(value_type::v(), {})};
        oe->add_chunk(generate_wrapper(*ia, ret));
        oe->add_function_decl(
            0x70000000fff0ull,
            "__arancini____libc_start_main_return_wrapper");
    }

    // Generate decls for external functions found in the relocation table

    if (!cmdline.count("no-static") && plt_tab && dyn_sym) {
        for (const auto &rs : relocations) {
            for (auto r : rs->relocations()) {
                auto sym_idx = r.symbol();
                auto dst = r.offset();
                auto sym = dyn_sym->symbols().at(sym_idx);
                if (!sym.is_func())
                    continue;

                ::util::global_logger.debug("Searching decl for {} @ {:#x}\n",
                                            sym.name(), dst);
                for (const auto &st : plt_tab->stubs()) {
                    if (st.second == dst) {
                        ::util::global_logger.debug(
                            "Adding decl for {} @ {:#x}\n", sym.name(),
                            st.first);
                        std::string decl_name = "__arancini__" + sym.name();
#ifdef NLIB
                        if (nlibs.has_value() &&
                            nlibs->native_functions().count(sym.name())) {
                            decl_name += "_wrapper";
                        }
#endif
                        oe->add_function_decl(st.first, decl_name);
                    }
                }
            next:;
            }
        }
    }
    // Generate a dot graph of the IR if required
    if (cmdline.count("graph")) {
        generate_dot_graph(*oe, cmdline.at("graph").as<std::string>());
    }

    // Execute required optimisations from the command line
    if (!cmdline.count("disable-flag-opt")) {
        optimise(*oe, cmdline);
    }

    // Generate a dot graph of the optimized IR if required
    if (cmdline.count("graph")) {
        std::string opt_filename = cmdline.at("graph").as<std::string>();
        opt_filename = opt_filename.substr(0, opt_filename.find_last_of('.'));
        opt_filename += ".opt.dot";
        generate_dot_graph(*oe, opt_filename);
    }

    // If the main output command-line option was not specified, then don't go
    // any further.
    if (!cmdline.count("output")) {
        return;
    }

    // Invoke the output engine, and tell it to write to a temporary file.
    oe->generate();

    // --------------- //

    // An output file was specified, so continue to build the translated binary.
    std::string cxx_compiler =
        cmdline.at("cxx-compiler-path").as<std::string>();

    if (cmdline.count("wrapper")) {
        cxx_compiler =
            cmdline.at("wrapper").as<std::string>() + " " + cxx_compiler;
    }

    std::string arancini_runtime_lib_path =
        cmdline.at("runtime-lib-path").as<std::string>();
    auto dir_start = arancini_runtime_lib_path.rfind("/");
    std::string arancini_runtime_lib_dir =
        arancini_runtime_lib_path.substr(0, dir_start);

    std::string debug_info = cmdline.count("debug-gen") ? " -g" : " -O3";

    std::string verbose_link =
        cmdline.count("verbose-link") ? " -Wl,--verbose" : "";

    if (cmdline.count("no-script")) {
        if (elf.type() == elf_type::exec) {
            run_or_fail(cxx_compiler + " -o " +
                        cmdline.at("output").as<std::string>() +
                        " -no-pie -latomic " + intermediate_file->name() +
                        " -l arancini-runtime -L " + arancini_runtime_lib_dir +
                        " -Wl,-rpath=" + arancini_runtime_lib_dir +
                        " -Wl,-z,now" + debug_info + verbose_link);
        } else if (elf.type() == elf::elf_type::dyn) {
            run_or_fail(
                cxx_compiler + " -o " + cmdline.at("output").as<std::string>() +
                " -shared " + intermediate_file->name() + " -L " +
                arancini_runtime_lib_dir + " -l arancini-runtime -Wl,-rpath=" +
                arancini_runtime_lib_dir + " -Wl,-z,now" + debug_info +
                verbose_link);
        }
        return;
    }

    // Generate loadable sections
    std::vector<std::shared_ptr<program_header>> load_phdrs;
    std::vector<std::shared_ptr<program_header>> tls;

    // For each program header, determine whether or not it's loadable, and
    // generate a corresponding temporary file containing the binary contents of
    // the segment.
    for (const auto &p : elf.program_headers()) {
        if (p->type() == program_header_type::loadable) {
            load_phdrs.push_back(p);
        } else if (p->type() == program_header_type::tls) {
            tls.push_back(p);
        }
    }

    // Now, we need to create an assembly file that includes the binary data for
    // each program header, defines all dynsyms of the input binary with
    // `__guest__` prefix, verbatim copies all relocations of the input binary
    // and some metadata
    auto phobjsrc = tf.create_file(prefix, ".S");

    std::map<uint64_t, std::string> ifuncs =
        generate_guest_sections(phobjsrc, elf, load_phdrs, filename, dyn_sym,
                                relocations, relocations_r, sym_t, tls,
                                native_symbol_addrs);

    auto init_exec_src = tf.create_file(prefix, ".c");
    {
        auto s = init_exec_src->open();
        s << "#include <stdio.h>\n"
          << "#include <unistd.h>\n"
          << "#include <stdint.h>\n"
          << "#include <stdlib.h>\n"
          << "#include <ctype.h>\n"
          << "#include <string.h>\n"
          << "extern \"C\" FILE *__guest__stdout __attribute__((weak)) = nullptr;\n"
          << "extern \"C\" FILE *__guest__stderr __attribute__((weak)) = nullptr;\n"
          << "extern \"C\" char *__guest__optarg __attribute__((weak)) = nullptr;\n"
          << "extern \"C\" char *optarg;\n"
          << "extern \"C\" int __arancini_getopt(int argc, char **argv, const char *optstring) {\n"
          << "  int ret = getopt(argc, argv, optstring);\n"
          << "  if (&__guest__optarg) __guest__optarg = optarg;\n"
          << "  return ret;\n"
          << "}\n"
          << "extern \"C\" int arancini_call_guest2_i32(uint64_t guest_addr, uint64_t arg0, uint64_t arg1);\n"
          << "static thread_local uint64_t __arancini_qsort_compar;\n"
          << "static int __arancini_qsort_cmp(const void *a, const void *b) {\n"
          << "  return arancini_call_guest2_i32(__arancini_qsort_compar, (uint64_t)a, (uint64_t)b);\n"
          << "}\n"
          << "extern \"C\" void __arancini_qsort(void *base, uint64_t nmemb, uint64_t size, uint64_t compar) {\n"
          << "  uint64_t prev = __arancini_qsort_compar;\n"
          << "  __arancini_qsort_compar = compar;\n"
          << "  qsort(base, nmemb, size, __arancini_qsort_cmp);\n"
          << "  __arancini_qsort_compar = prev;\n"
          << "}\n"
          << "static int __arancini_printf_arg_kinds(const char *fmt, int *kinds, int max) {\n"
          << "  int n = 0;\n"
          << "  for (const char *p = fmt; p && *p && n < max; ++p) {\n"
          << "    if (*p != '%') continue;\n"
          << "    if (*++p == '%') continue;\n"
          << "    while (*p && strchr(\"#0- +'\", *p)) ++p;\n"
          << "    if (*p == '*') { kinds[n++] = 0; ++p; }\n"
          << "    else while (*p && isdigit((unsigned char)*p)) ++p;\n"
          << "    if (*p == '.') {\n"
          << "      ++p;\n"
          << "      if (*p == '*') { if (n < max) kinds[n++] = 0; ++p; }\n"
          << "      else while (*p && isdigit((unsigned char)*p)) ++p;\n"
          << "    }\n"
          << "    while (*p && strchr(\"hljztL\", *p)) ++p;\n"
          << "    if (!*p || *p == 'm') continue;\n"
          << "    kinds[n++] = strchr(\"aAeEfFgG\", *p) != 0;\n"
          << "  }\n"
          << "  return n;\n"
          << "}\n"
          << "template <typename... Args>\n"
          << "static int __arancini_printf_dispatch(const char *fmt, const int *kinds, int n, const uint64_t *g, const double *f, int gi, int fi, Args... args) {\n"
          << "  if (n <= 0) {\n"
          << "    if constexpr (sizeof...(Args) == 0) { int ret = fputs(fmt, stdout); return ret < 0 ? ret : (int)strlen(fmt); }\n"
          << "    else return printf(fmt, args...);\n"
          << "  }\n"
          << "  if constexpr (sizeof...(Args) >= 10) {\n"
          << "    return printf(fmt, args...);\n"
          << "  } else {\n"
          << "    return *kinds ? __arancini_printf_dispatch(fmt, kinds + 1, n - 1, g, f, gi, fi + 1, args..., f[fi])\n"
          << "                  : __arancini_printf_dispatch(fmt, kinds + 1, n - 1, g, f, gi + 1, fi, args..., g[gi]);\n"
          << "  }\n"
          << "}\n"
          << "extern \"C\" int __arancini_printf(const char *fmt, uint64_t rsi, uint64_t rdx, uint64_t rcx, uint64_t r8, uint64_t r9, double f0, double f1, double f2, double f3, double f4, double f5, double f6, double f7) {\n"
          << "  uint64_t g[] = {rsi, rdx, rcx, r8, r9};\n"
          << "  double f[] = {f0, f1, f2, f3, f4, f5, f6, f7};\n"
          << "  int kinds[10];\n"
          << "  int n = __arancini_printf_arg_kinds(fmt, kinds, 10);\n"
          << "  return __arancini_printf_dispatch(fmt, kinds, n, g, f, 0, 0);\n"
          << "}\n"
          << "template <typename... Args>\n"
          << "static int __arancini_fprintf_dispatch(FILE *stream, const char *fmt, const int *kinds, int n, const uint64_t *g, const double *f, int gi, int fi, Args... args) {\n"
          << "  if (n <= 0) {\n"
          << "    if constexpr (sizeof...(Args) == 0) { int ret = fputs(fmt, stream); return ret < 0 ? ret : (int)strlen(fmt); }\n"
          << "    else return fprintf(stream, fmt, args...);\n"
          << "  }\n"
          << "  if constexpr (sizeof...(Args) >= 10) {\n"
          << "    return fprintf(stream, fmt, args...);\n"
          << "  } else {\n"
          << "    return *kinds ? __arancini_fprintf_dispatch(stream, fmt, kinds + 1, n - 1, g, f, gi, fi + 1, args..., f[fi])\n"
          << "                  : __arancini_fprintf_dispatch(stream, fmt, kinds + 1, n - 1, g, f, gi + 1, fi, args..., g[gi]);\n"
          << "  }\n"
          << "}\n"
          << "extern \"C\" int __arancini_fprintf(FILE *stream, const char *fmt, uint64_t rdx, uint64_t rcx, uint64_t r8, uint64_t r9, double f0, double f1, double f2, double f3, double f4, double f5, double f6, double f7) {\n"
          << "  uint64_t g[] = {rdx, rcx, r8, r9};\n"
          << "  double f[] = {f0, f1, f2, f3, f4, f5, f6, f7};\n"
          << "  int kinds[10];\n"
          << "  int n = __arancini_printf_arg_kinds(fmt, kinds, 10);\n"
          << "  return __arancini_fprintf_dispatch(stream, fmt, kinds, n, g, f, 0, 0);\n"
          << "}\n"
          << "static __attribute__((constructor)) void init_exec(void) {\n"
          << "  if (&__guest__stdout) __guest__stdout = stdout;\n"
          << "  if (&__guest__stderr) __guest__stderr = stderr;\n"
          << "}\n";
    }

    if (!cmdline.count("static-binary")) {
        std::string libs;

        if (cmdline.count("library")) {
            std::stringstream stringstream;
            for (const auto &item :
                 cmdline.at("library").as<std::vector<std::string>>()) {
                stringstream << " " << item;
            }
            libs = stringstream.str();
        }

        {
            std::stringstream stringstream;
            for (const auto &nlib : needed_nlibs) {

                if (nlib.find('/') != std::string::npos) {
                    // Path not file name
                    stringstream << " " << nlib;
                } else { // File name
                    if ((strncmp(nlib.c_str(), "lib", 3) == 0) &&
                        (strncmp(nlib.c_str() + (nlib.size() - 3), ".so", 3) ==
                         0)) {
                        stringstream
                            << " -l"
                            << nlib.substr(3, nlib.size() -
                                                  6); // Starts with lib and
                                                      // ends with .so use -l
                    } else {
                        stringstream << " " << nlib;
                    }
                }
            }

            libs += stringstream.str();
        }

        if (elf.type() == elf::elf_type::exec) {
            // Generate the final output binary by compiling everything
            // together.
            run_or_fail(fmt::format(
                "{} -o {} -no-pie -latomic {} {} {} {} "
                "-larancini-runtime -L {} -Wl,-T,{}.exec.lds "
                "-Wl,-rpath={} -Wl,-z,now {} {}",
                cxx_compiler, cmdline.at("output").as<std::string>(),
                intermediate_file->name(), libs, phobjsrc->name(),
                init_exec_src->name(), arancini_runtime_lib_dir, architecture,
                arancini_runtime_lib_dir, debug_info, verbose_link));
        } else if (elf.type() == elf::elf_type::dyn) {
            // Generate the final output library by compiling everything
            // together.
            std::string tls_defines =
                tls.empty()
                    ? ""
                    : " -DTLS_LEN=" + std::to_string(tls[0]->data_size()) +
                          " -DTLS_SIZE=" + std::to_string(tls[0]->mem_size()) +
                          " -DTLS_ALIGN=" + std::to_string(tls[0]->align());

            run_or_fail(
                cxx_compiler + " -o " + cmdline.at("output").as<std::string>() +
                " -fPIC -shared " + intermediate_file->name() + " " +
                phobjsrc->name() + tls_defines + " init_lib.c -L " +
                arancini_runtime_lib_dir + " -l arancini-runtime " + libs +
                fmt::format(" -Wl,-T,lib.{}.lds -Wl,-rpath={} -Wl,-z,now {}",
                            architecture, arancini_runtime_lib_dir,
                            debug_info));
        } else {
            throw std::runtime_error("Input elf type must be either an "
                                     "executable or shared object.");
        }

    } else {
        std::string arancini_runtime_lib_dir =
            cmdline.at("static-binary").as<std::string>();

        if (elf.type() != elf::elf_type::exec) {
            throw std::runtime_error(
                "Can't generate a static binary from a shared object.");
        }

        // Generate the final output binary by compiling everything together.
        run_or_fail(fmt::format(
            "{} -o {} -no-pie -latomic -static-libgcc -static-libstdc++ {} {} "
            "-L {} -larancini-runtime-static -larancini-input-x86-static "
            "-larancini-output-riscv64-static -larancini-ir-static -L {}"
            "/../../obj -l xed {} -Wl,-T,{}.exec.lds,-rpath={}",
            cxx_compiler, cmdline.at("output").as<std::string>(),
            intermediate_file->name(), phobjsrc->name(),
            arancini_runtime_lib_dir, arancini_runtime_lib_dir, debug_info,
            architecture, arancini_runtime_lib_dir));
    }

    // Patch relocations in result binary
    const auto &output = cmdline.at("output").as<std::string>();
    elf_reader elf1 = {output};

    elf1.parse();

    std::shared_ptr<symbol_table> generated_dynsym;
    std::shared_ptr<symbol_table> generated_symtab;
    std::vector<std::shared_ptr<rela_table>> generated_rela;

    for (auto &s : elf1.sections()) {
        if (s->type() == elf::section_type::dynamic_symbol_table) {
            auto st = std::static_pointer_cast<symbol_table>(s);
            generated_dynsym = std::move(st);
        } else if (s->type() == elf::section_type::symbol_table) {
            auto st = std::static_pointer_cast<symbol_table>(s);
            generated_symtab = std::move(st);
        } else if (s->type() == elf::section_type::relocation_addend) {
            auto st = std::static_pointer_cast<rela_table>(s);
            generated_rela.push_back(std::move(st));
        }
    }

    std::map<std::string, int> guest_symbol_to_index;
    std::map<std::string, uint64_t> guest_symbol_to_value;

    const auto record_guest_symbol = [&](const symbol &sym, size_t index,
                                         bool record_index) {
        const std::string &name = sym.name();
        constexpr const char *prefix = "__guest__";
        constexpr size_t prefix_len = 9;
        if (name.compare(0, prefix_len, prefix) != 0) {
            return;
        }
        const std::string guest_name = name.substr(prefix_len);
        if (record_index) {
            guest_symbol_to_index.emplace(guest_name, index);
        }
        if (sym.value()) {
            guest_symbol_to_value.emplace(guest_name, sym.value());
        }
    };

    const std::vector<symbol> &guest_symbols = generated_dynsym->symbols();
    for (size_t i = 0; i < guest_symbols.size(); ++i) {
        record_guest_symbol(guest_symbols[i], i, true);
    }
    if (generated_symtab) {
        for (const auto &sym : generated_symtab->symbols()) {
            record_guest_symbol(sym, 0, false);
        }
    }

    {
        std::ofstream file(cmdline.at("output").as<std::string>(),
                           std::ios::out | std::ios::binary | std::ios::in);

        for (const auto &relocs : generated_rela) {
            const std::vector<rela> &relocations1 = relocs->relocations();
            for (size_t i = 0; i < relocations1.size(); ++i) {
                const auto &reloc = relocations1[i];
                unsigned int transform = reloc.type() & 0xf0000000;
                if (transform ==
                    0x20000000) { // addend needs to be replaced with value of
                                  // symbol with name ifuncs[addend].
                    // ifunc tells us the symbol for the addend
                    uint64_t new_addend =
                        guest_symbols[guest_symbol_to_index
                                          [ifuncs[reloc.addend()].substr(9)]]
                            .value();
                    unsigned int buf = reloc.type() & ~0xf0000000;
                    file.seekp(relocs->file_offset() + 24 * i + 8);
                    file.write(reinterpret_cast<const char *>(&buf),
                               sizeof(buf));
                    file.seekp(4, std::ios::cur);
                    file.write(reinterpret_cast<const char *>(&new_addend),
                               sizeof(new_addend));
                    // Write new_addend to (relocs.file_offset() + 24 * i + 16)
                    // and reloc.type() & ~0xf0000000 to (relocs.file_offset() +
                    // 24 * i + 8)
                } else if (transform ==
                           0x10000000) { // symbol index needs to be adjusted to
                                         // point to correct index in target
                                         // dyn_sym table
                    const std::string &guest_name =
                        dyn_sym->symbols()[reloc.symbol()].name();
                    unsigned int buf = reloc.type() & ~0xf0000000;
                    file.seekp(relocs->file_offset() + 24 * i + 8);
                    if (auto sym_index = guest_symbol_to_index.find(guest_name);
                        sym_index != guest_symbol_to_index.end()) {
                        unsigned int new_symbol = sym_index->second;
                        file.write(reinterpret_cast<const char *>(&buf),
                                   sizeof(buf));
                        file.write(reinterpret_cast<const char *>(&new_symbol),
                                   sizeof(new_symbol));
                    } else if (auto sym_value = guest_symbol_to_value.find(guest_name);
                               sym_value != guest_symbol_to_value.end()) {
#if defined(ARCH_AARCH64)
                        constexpr int host_relative_reloc = R_AARCH64_RELATIVE;
#elif defined(ARCH_RISCV64)
                        constexpr int host_relative_reloc = R_RISCV_RELATIVE;
#else
                        constexpr int host_relative_reloc = 0;
#endif
                        unsigned int no_symbol = 0;
                        uint64_t addend = sym_value->second + reloc.addend();
                        file.write(reinterpret_cast<const char *>(
                                       &host_relative_reloc),
                                   sizeof(host_relative_reloc));
                        file.write(reinterpret_cast<const char *>(&no_symbol),
                                   sizeof(no_symbol));
                        file.write(reinterpret_cast<const char *>(&addend),
                                   sizeof(addend));
                    } else {
                        throw std::runtime_error("Unable to resolve generated guest symbol " +
                                                 guest_name);
                    }
                    // Write new_symbol to (relocs.file_offset() + 24 * i + 12)
                    // and reloc.type() & ~0xf0000000 to (relocs.file_offset() +
                    // 24 * i + 8), or rewrite the relocation as relative when
                    // the generated guest symbol is not exported in .dynsym.
                } else if (transform) {
                    throw std::runtime_error(
                        "Invalid relocation transform type " +
                        std::to_string(transform));
                }
            }
        }
        file.close();
    }
}

void txlat_engine::add_symbol_to_output(
    const std::vector<std::shared_ptr<program_header>> &phbins,
    const std::map<off_t, unsigned int> &end_addresses, const symbol &sym,
    std::ofstream &s, std::map<uint64_t, std::string> &ifuncs,
    const std::map<std::string, uint64_t> &native_symbol_addrs,
    bool force_global, bool omit_prefix) {
    auto type = sym.type();

    unsigned int i = end_addresses.upper_bound(sym.value())->second;
    const std::shared_ptr<program_header> &phdr = phbins[i / 2];

    auto name = omit_prefix ? sym.name() : "__guest__" + sym.name();
    if (strcmp(type, "STT_GNU_IFUNC") == 0) {

        if (sym.section_index() != SHN_UNDEF) {
            s << ".set \"" << name << "__ifunc\", __PH_" << std::dec << i / 2
              << "_DATA_" << i % 2 << " + "
              << sym.value() - phdr->address() - (i % 2) * (phdr->data_size())
              << '\n';
        }

        s << ".type \"" << name << "__ifunc\", "
          << "STT_FUNC" << '\n'
          << ".hidden \"" << name
          << "__ifunc\"\n"

          // Generate a stub that mimics a resolver with the following assembly
          // code
          /*						  name:
           *  ff 25 00 00 00 00       jmp    QWORD PTR [rip+name_resolve]
           *  57                      push   rdi
           *  56                      push   rsi
           *  52                      push   rdx
           *  51                      push   rcx
           *  41 50                   push   r8
           *  51                      push   rcx
           *  51                      push   rcx
           *  e8 00 00 00 00          call   name_ifunc
           *  41 59                   pop    r9
           *  41 58                   pop    r8
           *  59                      pop    rcx
           *  5a                      pop    rdx
           *  5e                      pop    rsi
           *  5f                      pop    rdi
           *  48 89 05 00 00 00 00    mov    QWORD PTR [rip+name_resolve],rax
           *  ff e0                   jmp    rax
           */

          << ".section .data.resolve\n"
          << '\"' << name << "__resolve\": .quad 1f\n"
          << ".section .data.ifunc\n"
          << '\"' << name << "\":\n"
          << ".byte 0xff, 0x25\n"
          << "0: .zero 4\n"
          << "1: .byte 0x57, 0x56, 0x52, 0x51, 0x41, 0x50, 0x41, 0x51, 0xe8\n"
          << "2: .zero 4\n"
          << ".byte 0x41, 0x59, 0x41, 0x58, 0x59, 0x5a, 0x5e, 0x5f, 0x48, "
             "0x89, 0x05\n"
          << "3: .zero 4\n"
          << ".byte 0xff, 0xe0\n"
          << ".reloc 0b, R_RISCV_32_PCREL, \"" << name << "__resolve\" - 4\n"
          << ".reloc 2b, R_RISCV_32_PCREL, \"" << name << "__ifunc\" - 4\n"
          << ".reloc 3b, R_RISCV_32_PCREL, \"" << name << "__resolve\" - 4\n";

        type = "STT_FUNC";
        ifuncs[sym.value()] = name;

    } else if (sym.section_index() != SHN_UNDEF) {
        s << ".set \"" << name << "\", __PH_" << std::dec << i / 2 << "_DATA_"
          << i % 2 << " + "
          << sym.value() - phdr->address() - (i % 2) * (phdr->data_size())
          << '\n'
          << ".size \"" << name << "\", " << std::dec << sym.size() << '\n';
    } else if (auto native = native_symbol_addrs.find(sym.name());
               native != native_symbol_addrs.end()) {
        s << ".set \"" << name << "\", 0x" << std::hex << native->second
          << '\n';
    }
    if (force_global || sym.is_global()) {
        s << ".globl \"" << name << "\"\n";
    } else if (sym.is_weak()) {
        s << ".weak \"" << name << "\"\n";
    }

    s << ".type \"" << name << "\", " << type << '\n';
    if (sym.is_hidden() & !force_global) {
        s << ".hidden \"" << name << "\"\n";
    } else if (sym.is_internal()) {
        s << ".internal \"" << name << "\"\n";
    } else if (sym.is_protected() & !force_global) {
        s << ".protected \"" << name << "\"\n";
    }
}

std::shared_ptr<chunk>
txlat_engine::generate_wrapper(arancini::input::input_arch &ia,
                               const nlib_function &func) {
    default_ir_builder irb(ia.get_internal_function_resolver(), true);

    auto start = std::chrono::high_resolution_clock::now();
    ia.gen_wrapper(irb, func);
    auto dur = std::chrono::high_resolution_clock::now() - start;

    return irb.get_chunk();
}

/*
  This function uses an x86 implementation of the input_architecture class to
  lift x86 symbol sections to the Arancini IR.
*/
std::shared_ptr<chunk>
txlat_engine::translate_symbol(arancini::input::input_arch &ia,
                               elf_reader &reader, const symbol &sym) {
    ::util::global_logger.info(
        "Translating symbol {}; value={:x} size={} section={}\n", sym.name(),
        sym.value(), sym.size(), sym.section_index());

    auto section = reader.get_section(sym.section_index());
    if (!section) {
        throw std::runtime_error("unable to resolve symbol section");
    }

    off_t symbol_offset_in_section = sym.value() - section->address();

    const void *symbol_data =
        (const void *)((uintptr_t)section->data() + symbol_offset_in_section);

    default_ir_builder irb(ia.get_internal_function_resolver(), true);

    auto start = std::chrono::high_resolution_clock::now();
    ia.translate_chunk(irb, sym.value(), symbol_data, sym.size(), false,
                       "__arancini__" + sym.name());
    auto dur = std::chrono::high_resolution_clock::now() - start;

    ::util::global_logger.info(
        "Symbol translation time: {} us\n",
        std::chrono::duration_cast<std::chrono::microseconds>(dur).count());
    return irb.get_chunk();
}

void txlat_engine::generate_dot_graph(
    arancini::output::o_static::static_output_engine &oe,
    std::string filename) {
    std::ostream *o;

    std::cout << "Generating dot graph to: " << filename << std::endl;

    if (filename == "-") {
        o = &std::cout;
    } else {
        o = new std::ofstream(filename);
        if (!((std::ofstream *)o)->is_open()) {
            throw std::runtime_error("unable to open file for graph output");
        }
    }

    dot_graph_generator dgg(*o);
    for (auto c : oe.chunks()) {
        c->accept(dgg);
    }

    if (o != &std::cout) {
        delete o;
    }
}

void txlat_engine::optimise(
    arancini::output::o_static::static_output_engine &oe,
    const boost::program_options::variables_map &cmdline) {
    auto start = std::chrono::high_resolution_clock::now();
    deadflags_opt_visitor deadflags;
    for (auto c : oe.chunks()) {
        c->accept(deadflags);
    }
    auto dur = std::chrono::high_resolution_clock::now() - start;
    ::util::global_logger.info(
        "Optimisation: dead flags elimination pass took {} us\n",
        std::chrono::duration_cast<std::chrono::microseconds>(dur).count());
}

std::map<uint64_t, std::string> txlat_engine::generate_guest_sections(
    const std::shared_ptr<util::basefile> &phobjsrc, elf::elf_reader &elf,
    const std::vector<std::shared_ptr<elf::program_header>> &load_phdrs,
    const std::basic_string<char> &filename,
    const std::shared_ptr<symbol_table> &dyn_sym,
    const std::vector<std::shared_ptr<elf::rela_table>> &relocations,
    const std::vector<std::shared_ptr<elf::relr_array>> &relocations_r,
    const std::shared_ptr<symbol_table> &sym_t,
    const std::vector<std::shared_ptr<elf::program_header>> &tls,
    const std::map<std::string, uint64_t> &native_symbol_addrs) {
    std::map<uint64_t, std::string> ifuncs;
    std::map<off_t, unsigned int> end_addresses;
    auto s = phobjsrc->open();

    // FIXME Currently hardcoded to current directory. Not sure what else to do
    // since the linker script needs to have this path in it.
    auto l = std::ofstream("guest-sections.lds");

    if (tls.size() == 1) {
        if (elf.type() == elf::elf_type::exec) {
            size_t offset = tls[0]->mem_size() +
                            (tls[0]->align() -
                             1); // Assume maximum misalignment penalty.
                                 // Probably actually less. Correct at runtime.
            s << ".section .data\nguest_exec_tls:\n"
              << ".quad 0\n"     // next = NULL
              << ".quad guest_tls\n" // image = guest_tls
              << ".quad " << std::dec << tls[0]->data_size() << '\n' // len
              << ".quad " << tls[0]->mem_size() << '\n'              // size
              << ".quad " << tls[0]->align() << '\n'                 // align
              << ".quad " << offset << '\n'                          // offset
              << ".globl guest_exec_tls\n"
              << "tls_offset:\n"
              << ".quad " << offset << '\n'
              << ".globl tls_offset\n";
        }
    } else if (tls.size() > 1) {
        throw std::runtime_error("More than 1 TLS PHDR unsupported");
    }

    // For each segment...
    for (unsigned int i = 0; i < load_phdrs.size(); i++) {

        auto phdr = load_phdrs[i];
        end_addresses[phdr->address() + phdr->data_size()] = 2 * i;

        off_t address = phdr->address();

        // Add 2 sections per PT_LOAD header (one for initialized and one for
        // uninitialized data.
        l << ".gph.load" << std::dec << i << ".1 " << address << ": { *("
          << ".gph.load" << std::dec << i << ".1) } :gphdr" << std::dec << i
          << '\n';
        l << ".gph.load" << std::dec << i << ".2 : { *("
          << ".gph.load" << std::dec << i << ".2) } :gphdr" << std::dec << i
          << '\n';

        s << ".section .gph.load" << std::dec << i << ".1, \"a";
        if (phdr->flags() & PF_W) {
            s << 'w';
        }
        //			if (phdr->flags() & PF_X) {
        //				s << 'x';
        //			}
        s << "\"\n";

        if (tls.size() == 1) {
            // Other cases handled below

            // TLS initialized data (.tdata) is part of one of the LOAD headers
            // (typically at the start), add a symbol so we can initialize it at
            // runtime.
            if (phdr->offset() == tls[0]->offset()) {
                s << "guest_tls:\n";
            }
        }

        s << ".ifndef guest_base\nguest_base:\n.globl guest_base\n.hidden "
             "guest_base\n";
        if (elf.type() == elf::elf_type::exec) {
            s << "guest_exec_base:\n.globl guest_exec_base\n";
        }
        s << ".endif\n";

        s << "__PH_" << std::dec << i << "_DATA_0: .incbin \"" << filename
          << "\", " << phdr->offset() << ", " << phdr->data_size() << std::endl;
        if (phdr->mem_size() - phdr->data_size()) {
            end_addresses[phdr->address() + phdr->mem_size()] = 2 * i + 1;
            s << ".section .gph.load" << std::dec << i << ".2, \"a";
            if (phdr->flags() & PF_W) {
                s << 'w';
            }
            //				if (phdr->flags() & PF_X) {
            //					s << 'x';
            //				}
            s << "\", @nobits\n";
            // Using .zero n does not work with symbols
            s << "__PH_" << std::dec << i << "_DATA_1: .rept " << std::dec
              << phdr->mem_size() - phdr->data_size() << "\n.byte 0\n.endr\n";
        }
    }

    if (dyn_sym) {
        for (const auto &sym : dyn_sym->symbols()) {
            add_symbol_to_output(load_phdrs, end_addresses, sym, s, ifuncs,
                                 native_symbol_addrs);
        }
    }

    for (const auto &sym : sym_t->symbols()) {
        if (sym.name() == "_DYNAMIC" && sym.section_index() != SHN_UNDEF) {

            add_symbol_to_output(load_phdrs, end_addresses, sym, s, ifuncs,
                                 native_symbol_addrs, true);
            s << ".hidden __guest___DYNAMIC\n";
            if (elf.type() == elf::elf_type::exec) {
                symbol sy{"guest_exec_DYNAMIC", sym.value(), sym.size(),
                          sym.section_index(),  sym.info(),  0};
                add_symbol_to_output(load_phdrs, end_addresses, sy, s, ifuncs,
                                     native_symbol_addrs, true, true);
            }
        }
        static const std::set<std::string> symbols_to_copy_global{
            "main_ctor_queue",    "__malloc_replaced", "__libc",
            "__thread_list_lock", "__sysinfo",         "__environ"};
        if (symbols_to_copy_global.count(sym.name())) {
            add_symbol_to_output(load_phdrs, end_addresses, sym, s, ifuncs,
                                 native_symbol_addrs, true);
        }
    }

    // Manually emit relocations into the .grela section
    s << ".section .grela, \"a\"\n";

    for (const auto &relocs : relocations_r) {
        for (const auto &reloc : relocs->relocations()) {
            unsigned int i = end_addresses.upper_bound(reloc)->second;
            const std::shared_ptr<program_header> &phdr = load_phdrs[i / 2];

            // Reading this here because now the file_offset can be calculated
            // from the encompassing phdr
            uint64_t addend =
                elf.read_relr_addend(phdr->offset() - phdr->address() + reloc);

            // FIXME hardcoded 3 as RELATIVE reloc type
            s << ".quad 0x" << std::hex << reloc << "\n.quad 3\n.quad 0x"
              << addend << '\n';
        }
    }

    // A Relocation consists of 3 quad words. First the offset, then type in the
    // high 32 bit and symbol index in the low 32 bit of the second and the
    // addend in the third
    for (const auto &relocs : relocations) {
        for (const auto &reloc : relocs->relocations()) {
            if (reloc.is_irelative()) {
                // Use a relative reloc to the stub function instead. Identify
                // the needed function by the original addend.
                if (ifuncs.count(reloc.addend())) {
                    s << ".quad 0x" << std::hex << reloc.offset()
                      << "\n.quad 0x20000003\n.quad 0x" << reloc.addend()
                      << '\n';
                }
            } else if (reloc.is_tpoff()) {
                // For TP relative relocations, we only know the offset after
                // mapping, but the emulated TLS is separate from the host TLS,
                // so we can only perform those manually in library init. Add an
                // array of offset, addend pairs to iterate over.

                if (elf.type() == elf_type::exec) {
                    throw std::runtime_error(
                        "TP relative reloc in binary not supported.");
                }

                s << ".section .data.tp_reloc\n.ifndef "
                     "__TPREL_INIT\n__TPREL_INIT:\n.endif\n"
                  << "0: .quad 0x" << std::hex << reloc.offset() << ", 0x"
                  << reloc.addend() << '\n'
                  << ".reloc 0b, R_RISCV_64, 0x" << std::hex << reloc.offset()
                  << '\n'
                  << ".section .grela\n";
            } else if (reloc.is_dtpmod()) {

                if (elf.type() == elf_type::exec) {
                    throw std::runtime_error(
                        "DTPMOD reloc in binary not supported.");
                }

                if (reloc.symbol() != 0 || reloc.addend() != 0) {
                    throw std::runtime_error(
                        "DTPMOD reloc with non-0 symbol/addend unsupported.");
                }

                s << ".section .data.dtpmod_reloc\n.ifndef "
                     "__DTPMOD_INIT\n__DTPMOD_INIT:\n.endif\n"
                  << "0: .quad 0x" << std::hex << reloc.offset() << '\n'
                  << ".reloc 0b, R_RISCV_64, 0x" << std::hex << reloc.offset()
                  << '\n'
                  << ".section .grela\n";

            } else if (dyn_sym &&
                       native_symbol_addrs.count(
                           dyn_sym->symbols()[reloc.symbol()].name())) {
#if defined(ARCH_AARCH64)
                constexpr int host_relative_reloc = R_AARCH64_RELATIVE;
#elif defined(ARCH_RISCV64)
                constexpr int host_relative_reloc = R_RISCV_RELATIVE;
#else
                constexpr int host_relative_reloc = 0;
#endif
                s << ".quad 0x" << std::hex << reloc.offset() << "\n.int 0x"
                  << host_relative_reloc << "\n.int 0x0\n.quad 0x"
                  << native_symbol_addrs.at(
                         dyn_sym->symbols()[reloc.symbol()].name())
                  << '\n';
            } else if (reloc.is_relative()) {
                s << ".quad 0x" << std::hex << reloc.offset() << "\n.int 0x"
                  << reloc.type_on_host() << "\n.int 0x" << reloc.symbol()
                  << "\n.quad 0x" << reloc.addend() << '\n';
            } else if (reloc.is_copy()) {
                // The guest copy relocation destination is already present in
                // the embedded data.  Do not emit a host R_*_COPY relocation to
                // the prefixed guest symbol; libc globals that are intentionally
                // shared with nlib wrappers are initialized by the runtime.
            } else {
                // Mark this relocation as needing adjustment on the symbol
                // index (it needs to match the index of the symbol in the
                // generated binary). Set the 4th highest bit of the type to
                // indicate this.
                s << ".quad 0x" << std::hex << reloc.offset() << "\n.int 0x"
                  << (0x10000000 | reloc.type_on_host()) << "\n.int 0x"
                  << reloc.symbol() << "\n.quad 0x" << reloc.addend() << '\n';
            }
        }
    }

    s << ".section .data.tp_reloc\n.ifndef "
         "__TPREL_INIT\n__TPREL_INIT:\n.endif\n.quad 0x0, 0x0\n"
      << ".globl __TPREL_INIT\n.type __TPREL_INIT, STT_OBJECT\n.size "
         "__TPREL_INIT, . - __TPREL_INIT \n.hidden __TPREL_INIT\n"
      << ".section .data.dtpmod_reloc\n.ifndef "
         "__DTPMOD_INIT\n__DTPMOD_INIT:\n.endif\n.quad 0x0\n"
      << ".globl __DTPMOD_INIT\n.type __DTPMOD_INIT, STT_OBJECT\n.size "
         "__DTPMOD_INIT, . - __DTPMOD_INIT \n.hidden __DTPMOD_INIT\n"
      << ".ifndef guest_tls\n.set guest_tls, 0\n.endif\n.globl "
         "guest_tls\n.hidden guest_tls\n";
    if (elf.type() == elf_type::exec) {
        s << ".ifndef tls_offset\ntls_offset:\n.quad 0\n.globl "
             "tls_offset\n.endif\n";
    }

    return ifuncs;
}
