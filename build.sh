#!/usr/bin/env bash

set -euo pipefail
umask 077

rid="${1:-}"
out_dir="${2:-}"

if [[ -z "$rid" || -z "$out_dir" ]]; then
    echo "Usage: build.sh <rid> <out_dir>" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

case "$rid" in
    win-*|osx-*)
        chmod +x "$script_dir/scripts/build-vcpkg.sh"
        "$script_dir/scripts/build-vcpkg.sh" "$rid" "$out_dir"
        ;;
    linux-*)
        if [[ "${USE_DOCKER:-}" == "1" ]]; then
            chmod +x "$script_dir/scripts/build-linux-docker.sh"
            "$script_dir/scripts/build-linux-docker.sh" "$rid" "$out_dir"
        else
            if [[ "$rid" == linux-musl-* ]]; then
                chmod +x "$script_dir/scripts/build-linux-container.sh"
                "$script_dir/scripts/build-linux-container.sh" "$rid" "$out_dir"
            else
                chmod +x "$script_dir/scripts/build-vcpkg.sh"
                "$script_dir/scripts/build-vcpkg.sh" "$rid" "$out_dir"
            fi
        fi
        ;;
    *)
        echo "Unsupported rid: $rid" >&2
        exit 1
        ;;
esac
