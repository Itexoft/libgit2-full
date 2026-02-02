#!/usr/bin/env bash

set -euo pipefail

rid="${1:-}"
out_dir="${2:-}"

if [[ -z "$rid" || -z "$out_dir" ]]; then
    echo "Usage: build-linux-docker.sh <rid> <out_dir>" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root_dir="$(cd "$script_dir/.." && pwd -P)"

case "$rid" in
    linux-x64)
        platform="linux/amd64"
        image="ubuntu:22.04"
        build_mode="vcpkg"
        ;;
    linux-arm64)
        platform="linux/arm64"
        image="ubuntu:22.04"
        build_mode="vcpkg"
        ;;
    linux-arm)
        platform="linux/arm/v7"
        image="ubuntu:22.04"
        build_mode="vcpkg"
        ;;
    linux-ppc64le)
        platform="linux/ppc64le"
        image="ubuntu:22.04"
        build_mode="vcpkg"
        ;;
    linux-musl-x64)
        platform="linux/amd64"
        image="alpine:3.19"
        build_mode="musl"
        ;;
    linux-musl-arm64)
        platform="linux/arm64"
        image="alpine:3.19"
        build_mode="musl"
        ;;
    linux-musl-arm)
        platform="linux/arm/v7"
        image="alpine:3.19"
        build_mode="musl"
        ;;
    *)
        echo "Unsupported linux rid: $rid" >&2
        exit 1
        ;;
esac

out_dir_rel="$out_dir"
if [[ "$out_dir_rel" == "$root_dir"/* ]]; then
    out_dir_rel="${out_dir_rel#$root_dir/}"
fi

container_out_dir="/src/$out_dir_rel"

if [[ "$build_mode" == "musl" ]]; then
    chmod +x "$root_dir/scripts/build-linux-container.sh"
    docker run --rm --platform "$platform" \
        -v "$root_dir:/src" \
        -w /src \
        "$image" \
        /bin/sh -c "apk add --no-cache bash && /bin/bash /src/scripts/build-linux-container.sh \"$rid\" \"$container_out_dir\""
else
    chmod +x "$root_dir/scripts/build-vcpkg.sh"
    docker run --rm --platform "$platform" \
        -v "$root_dir:/src" \
        -w /src \
        -e RID="$rid" \
        -e OUT_DIR="$container_out_dir" \
        "$image" \
        /bin/sh -c 'apt-get update && apt-get install -y --no-install-recommends build-essential cmake ninja-build git curl zip unzip tar pkg-config ca-certificates python3 linux-libc-dev && /src/scripts/build-vcpkg.sh "$RID" "$OUT_DIR"'
fi
