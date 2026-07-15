#include <arancini/util/tempfile-manager.h>
#include <arancini/util/tempfile.h>

#include <cerrno>
#include <climits>
#include <cstdlib>
#include <filesystem>
#include <stdexcept>
#include <system_error>
#include <unistd.h>
#include <vector>

using namespace arancini::util;

std::shared_ptr<basefile>
tempfile_manager::create_file(const std::string &prefix,
                              const std::string &suffix) {
    if (prefix.empty()) {
        if (suffix.size() > INT_MAX) {
            throw std::length_error("temporary-file suffix is too long");
        }

        auto name =
            (std::filesystem::temp_directory_path() / ("T-XXXXXX" + suffix))
                .string();
        std::vector<char> path(name.begin(), name.end());
        path.push_back('\0');

        const int fd = mkstemps(path.data(), static_cast<int>(suffix.size()));
        if (fd < 0) {
            throw std::system_error(errno, std::generic_category(),
                                    "unable to create temporary file");
        }
        if (close(fd) < 0) {
            const int error = errno;
            unlink(path.data());
            throw std::system_error(error, std::generic_category(),
                                    "unable to close temporary file");
        }

        try {
            auto t = std::make_shared<tempfile>(path.data());
            tempfiles_.push_back(t);
            return t;
        } catch (...) {
            unlink(path.data());
            throw;
        }
    }

    auto t = std::make_shared<persfile>(
        prefix + "P-" + std::to_string(std::rand() % 100) + suffix);
    tempfiles_.push_back(t);
    return t;
}
