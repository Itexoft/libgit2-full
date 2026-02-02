#!/usr/bin/env bash

set -euo pipefail

build_dir="${1:-}"
rid="${2:-}"
out_dir="${3:-}"

if [[ -z "$build_dir" || -z "$rid" || -z "$out_dir" ]]; then
    echo "Usage: copy-lib.sh <build_dir> <rid> <out_dir>" >&2
    exit 1
fi

mkdir -p "$out_dir"

case "$rid" in
    win-*)
        expected="libgit2.dll"
        file=$(find "$build_dir" -type f -name "$expected" | sort | head -n 1)
        if [[ -z "$file" ]]; then
            file=$(find "$build_dir" -type f -name "git2.dll" | sort | head -n 1)
        fi
        if [[ -z "$file" ]]; then
            echo "libgit2 DLL not found in $build_dir" >&2
            exit 1
        fi
        cp -f "$file" "$out_dir/$expected"
        ;;
    osx-*)
        expected="libgit2.dylib"
        file=$(find "$build_dir" -type f -name "$expected" | sort | head -n 1)
        if [[ -z "$file" ]]; then
            file=$(find "$build_dir" -type f -name "libgit2*.dylib" | sort | head -n 1)
        fi
        if [[ -z "$file" ]]; then
            echo "libgit2 dylib not found in $build_dir" >&2
            exit 1
        fi
        cp -Lf "$file" "$out_dir/$expected"
        ;;
    linux-*)
        expected="libgit2.so"
        file=$(find "$build_dir" -type f -name "$expected" | sort | head -n 1)
        if [[ -z "$file" ]]; then
            file=$(find "$build_dir" -type f -name "libgit2.so.*" | sort | head -n 1)
        fi
        if [[ -z "$file" ]]; then
            echo "libgit2 so not found in $build_dir" >&2
            exit 1
        fi
        cp -Lf "$file" "$out_dir/$expected"
        ;;
    *)
        echo "Unsupported rid: $rid" >&2
        exit 1
        ;;
esac
