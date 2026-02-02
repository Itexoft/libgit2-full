#!/usr/bin/env bash

set -euo pipefail

rid="${1:-}"
out_dir="${2:-}"

if [[ -z "$rid" || -z "$out_dir" ]]; then
    echo "Usage: build-vcpkg.sh <rid> <out_dir>" >&2
    exit 1
fi

libssh2_version="1.11.1"

if [[ "$rid" == linux-arm || "$rid" == linux-ppc64le ]]; then
    export VCPKG_FORCE_SYSTEM_BINARIES=1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd "$script_dir/.." && pwd -P)"
libgit2_dir="$root_dir/libgit2"
build_dir="$root_dir/.build/$rid"
vcpkg_root="${VCPKG_ROOT:-$root_dir/.vcpkg}"
overlay_triplets="$root_dir/vcpkg/triplets"

if [[ "$rid" == win-* ]]; then
    if ! command -v git >/dev/null 2>&1; then
        git_bin="/c/Program Files/Git/cmd"
        if [[ -d "$git_bin" ]]; then
            export PATH="$git_bin:$PATH"
        fi
    fi
    if ! command -v git >/dev/null 2>&1; then
        echo "git not found in PATH on Windows runner." >&2
        exit 1
    fi
fi

mkdir -p "$build_dir"

if [[ "$rid" == linux-* ]]; then
    unset CC CXX CFLAGS CXXFLAGS LDFLAGS CPPFLAGS SDKROOT MACOSX_DEPLOYMENT_TARGET
    export CC=gcc
    export CXX=g++
    if command -v dpkg >/dev/null 2>&1; then
        if ! dpkg -s linux-libc-dev >/dev/null 2>&1; then
            echo "linux-libc-dev is required for OpenSSL builds. Install it via: apt-get install linux-libc-dev" >&2
            exit 1
        fi
    fi
fi

if [[ ! -d "$vcpkg_root/.git" ]]; then
    if [[ -n "${VCPKG_COMMIT:-}" ]]; then
        git clone https://github.com/microsoft/vcpkg "$vcpkg_root"
    else
        git clone --depth 1 https://github.com/microsoft/vcpkg "$vcpkg_root"
    fi
fi

if [[ -n "${VCPKG_COMMIT:-}" ]]; then
    git -C "$vcpkg_root" fetch --depth 1 origin "$VCPKG_COMMIT"
    git -C "$vcpkg_root" checkout "$VCPKG_COMMIT"
fi

uname_out="$(uname -s)"
if [[ "$uname_out" == MINGW* || "$uname_out" == MSYS* || "$uname_out" == CYGWIN* ]]; then
    if ! command -v cygpath >/dev/null 2>&1; then
        echo "cygpath not found in PATH; cannot compute Windows paths for vcpkg." >&2
        exit 1
    fi
    bootstrap_ps1="$vcpkg_root/scripts/bootstrap.ps1"
    if [[ ! -f "$bootstrap_ps1" ]]; then
        echo "bootstrap.ps1 not found at $bootstrap_ps1" >&2
        exit 1
    fi
    vcpkg_root_win="$(cygpath -w "$vcpkg_root")"
    bootstrap_ps1_win="$(cygpath -w "$bootstrap_ps1")"
    if ! command -v powershell.exe >/dev/null 2>&1; then
        echo "powershell.exe not found in PATH; cannot bootstrap vcpkg." >&2
        exit 1
    fi
    VCPKG_DISABLE_METRICS=1 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$bootstrap_ps1_win" -disableMetrics
else
    VCPKG_DISABLE_METRICS=1 "$vcpkg_root/bootstrap-vcpkg.sh" -disableMetrics
fi

vcpkg_bin="$vcpkg_root/vcpkg"
if [[ "$uname_out" == MINGW* || "$uname_out" == MSYS* || "$uname_out" == CYGWIN* ]]; then
    vcpkg_bin="$vcpkg_root/vcpkg.exe"
    if [[ ! -f "$vcpkg_bin" ]]; then
        echo "vcpkg.exe not found after bootstrap at $vcpkg_bin" >&2
        exit 1
    fi
else
    if [[ ! -f "$vcpkg_bin" ]]; then
        echo "vcpkg binary not found after bootstrap at $vcpkg_bin" >&2
        exit 1
    fi
fi

libssh2_port="$vcpkg_root/ports/libssh2/vcpkg.json"
if [[ ! -f "$libssh2_port" ]]; then
    echo "libssh2 port metadata not found at $libssh2_port" >&2
    exit 1
fi
if ! grep -Eq "\"version\"\\s*:\\s*\"$libssh2_version\"" "$libssh2_port"; then
    echo "libssh2 port version mismatch; expected $libssh2_version" >&2
    exit 1
fi

if [[ "$rid" == win-* ]]; then
    if ! command -v cmake >/dev/null 2>&1; then
        cmake_bin="/c/Program Files/CMake/bin"
        if [[ -d "$cmake_bin" ]]; then
            export PATH="$cmake_bin:$PATH"
        fi
    fi
    if ! command -v cmake >/dev/null 2>&1; then
        echo "cmake not found in PATH on Windows runner." >&2
        exit 1
    fi
fi

case "$rid" in
    win-x86)
        triplet="x86-windows-static"
        cmake_arch="Win32"
        cmake_gen="Visual Studio 17 2022"
        ;;
    win-x64)
        triplet="x64-windows-static"
        cmake_arch="x64"
        cmake_gen="Visual Studio 17 2022"
        ;;
    win-arm64)
        triplet="arm64-windows-static"
        cmake_arch="ARM64"
        cmake_gen="Visual Studio 17 2022"
        ;;
    linux-x64)
        triplet="x64-linux-static"
        cmake_gen="Unix Makefiles"
        ;;
    linux-arm64)
        triplet="arm64-linux-static"
        cmake_gen="Unix Makefiles"
        ;;
    linux-arm)
        triplet="arm-linux-static"
        cmake_gen="Unix Makefiles"
        ;;
    linux-ppc64le)
        triplet="ppc64le-linux-static"
        cmake_gen="Unix Makefiles"
        ;;
    osx-x64)
        triplet="x64-osx-static"
        cmake_gen="Unix Makefiles"
        osx_arch="x86_64"
        ;;
    osx-arm64)
        triplet="arm64-osx-static"
        cmake_gen="Unix Makefiles"
        osx_arch="arm64"
        ;;
    *)
        echo "Unsupported rid for vcpkg build: $rid" >&2
        exit 1
        ;;
esac

if [[ "$rid" == linux-ppc64le ]]; then
    export VCPKG_MAX_CONCURRENCY=2
fi

VCPKG_OVERLAY_TRIPLETS="$overlay_triplets" VCPKG_DISABLE_METRICS=1 "$vcpkg_bin" install openssl libssh2 zlib --triplet "$triplet" --overlay-triplets="$overlay_triplets" --clean-after-build --disable-metrics --x-install-root="$vcpkg_root/installed"

cmake_args=(
    -S "$libgit2_dir"
    -B "$build_dir"
    -G "$cmake_gen"
    -DCMAKE_TOOLCHAIN_FILE="$vcpkg_root/scripts/buildsystems/vcpkg.cmake"
    -DVCPKG_TARGET_TRIPLET="$triplet"
    -DVCPKG_OVERLAY_TRIPLETS="$overlay_triplets"
    -DBUILD_SHARED_LIBS=ON
    -DBUILD_TESTS=OFF
    -DBUILD_CLI=OFF
    -DBUILD_EXAMPLES=OFF
    -DBUILD_BENCHMARKS=OFF
    -DBUILD_FUZZERS=OFF
    -DPKG_CONFIG_EXECUTABLE=
    -DUSE_SSH=libssh2
    -DUSE_HTTPS=OpenSSL
    -DUSE_AUTH_NEGOTIATE=OFF
    -DUSE_AUTH_NTLM=ON
    -DUSE_HTTP_PARSER=builtin
    -DUSE_REGEX=builtin
    -DUSE_COMPRESSION=builtin
    -DUSE_THREADS=ON
    -DUSE_NSEC=ON
    -DOPENSSL_USE_STATIC_LIBS=ON
)

libssh2_include="$vcpkg_root/installed/$triplet/include"
if [[ "$rid" == win-* ]]; then
    libssh2_lib="$vcpkg_root/installed/$triplet/lib/libssh2.lib"
else
    libssh2_lib="$vcpkg_root/installed/$triplet/lib/libssh2.a"
fi
if [[ -f "$libssh2_lib" ]]; then
    cmake_args+=("-DLIBSSH2_LIBRARY=$libssh2_lib" "-DLIBSSH2_INCLUDE_DIR=$libssh2_include")
fi

if [[ "$rid" == win-* ]]; then
    cmake_args+=("-A" "$cmake_arch" "-DLIBGIT2_FILENAME=libgit2")
elif [[ "$rid" == osx-* ]]; then
    cmake_args+=("-DCMAKE_BUILD_TYPE=Release" "-DCMAKE_FIND_LIBRARY_SUFFIXES=.a;.dylib" "-DUSE_I18N=ON" "-DCMAKE_OSX_ARCHITECTURES=$osx_arch")
else
    cmake_args+=("-DCMAKE_BUILD_TYPE=Release" "-DCMAKE_FIND_LIBRARY_SUFFIXES=.a;.so")
fi

cmake "${cmake_args[@]}"

if [[ "$rid" == win-* ]]; then
    cmake --build "$build_dir" --config Release
else
    cmake --build "$build_dir" --config Release
fi

"$root_dir/scripts/copy-lib.sh" "$build_dir" "$rid" "$out_dir"
