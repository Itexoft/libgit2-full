#!/usr/bin/env bash

set -euo pipefail

rid="${1:-}"
out_dir="${2:-}"

if [[ -z "$rid" || -z "$out_dir" ]]; then
    echo "Usage: build-linux-container.sh <rid> <out_dir>" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd "$script_dir/.." && pwd -P)"
libgit2_dir="$root_dir/libgit2"
build_dir="$root_dir/.build/$rid"
libssh2_version="1.11.1"

rm -rf "$build_dir"
mkdir -p "$build_dir" "$out_dir"

is_musl=0
if [[ -f /etc/alpine-release ]]; then
    is_musl=1
    apk add --no-cache build-base cmake pkgconfig openssl-dev openssl-libs-static zlib-dev git ca-certificates
else
    apt-get update
    apt-get install -y --no-install-recommends build-essential cmake pkg-config libssl-dev libssh2-1-dev zlib1g-dev ca-certificates
fi

unset CC CXX CFLAGS CXXFLAGS LDFLAGS CPPFLAGS SDKROOT MACOSX_DEPLOYMENT_TARGET
export CC=gcc
export CXX=g++

libssh2_static=""
libssh2_include=""
openssl_crypto=""
openssl_ssl=""
if [[ "$is_musl" == "1" ]]; then
    libssh2_prefix="$build_dir/libssh2"
    libssh2_src="$build_dir/libssh2-src"
    libssh2_build="$build_dir/libssh2-build"
    if [[ ! -f "$libssh2_prefix/lib/libssh2.a" ]]; then
        rm -rf "$libssh2_src" "$libssh2_build"
        git clone --depth 1 --branch "libssh2-$libssh2_version" https://github.com/libssh2/libssh2.git "$libssh2_src"
        cmake -S "$libssh2_src" -B "$libssh2_build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_INSTALL_PREFIX="$libssh2_prefix"
        build_jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
        cmake --build "$libssh2_build" --config Release -- -j "$build_jobs"
        cmake --install "$libssh2_build"
    fi
    libssh2_static="$libssh2_prefix/lib/libssh2.a"
    libssh2_include="$libssh2_prefix/include"
    openssl_crypto=$(find /usr/lib -name 'libcrypto.a' 2>/dev/null | head -n 1)
    openssl_ssl=$(find /usr/lib -name 'libssl.a' 2>/dev/null | head -n 1)
    if [[ -z "$openssl_crypto" || -z "$openssl_ssl" ]]; then
        echo "Static OpenSSL libraries not found; install openssl-libs-static." >&2
        exit 1
    fi
else
    libssh2_static=$(find /usr/lib /usr/local/lib -name 'libssh2.a' 2>/dev/null | head -n 1)
    if [[ -d /usr/include/libssh2 ]]; then
        libssh2_include="/usr/include"
    fi
fi

cmake_args=(
    -S "$libgit2_dir"
    -B "$build_dir"
    -DCMAKE_C_COMPILER=gcc
    -DCMAKE_BUILD_TYPE=Release
    "-DCMAKE_FIND_LIBRARY_SUFFIXES=.a;.so"
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

if [[ -n "$libssh2_static" ]]; then
    cmake_args+=("-DLIBSSH2_LIBRARY=$libssh2_static")
fi
if [[ -n "$libssh2_include" ]]; then
    cmake_args+=("-DLIBSSH2_INCLUDE_DIR=$libssh2_include")
fi
if [[ -n "$openssl_crypto" && -n "$openssl_ssl" ]]; then
    cmake_args+=("-DOPENSSL_ROOT_DIR=/usr" "-DOPENSSL_CRYPTO_LIBRARY=$openssl_crypto" "-DOPENSSL_SSL_LIBRARY=$openssl_ssl")
fi

cmake "${cmake_args[@]}"
build_jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
cmake --build "$build_dir" --config Release -- -j "$build_jobs"

"$root_dir/scripts/copy-lib.sh" "$build_dir" "$rid" "$out_dir"
