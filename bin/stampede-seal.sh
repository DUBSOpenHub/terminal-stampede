#!/usr/bin/env bash
# stampede-seal.sh — Canonical seal hash generator for Shadow Score
# Used by both the stampede skill (generation) and merge script (verification).
# Single source of truth for the hash format.
#
# Usage:
#   stampede-seal.sh generate <sealed-tests-dir>   # writes .seal-hash
#   stampede-seal.sh verify  <sealed-tests-dir>    # exits 0 if valid
#   stampede-seal.sh hash    <sealed-tests-dir>    # prints hash to stdout
set -euo pipefail

SEALED_DIR="${2:-}"

if [[ -z "$SEALED_DIR" ]] || [[ ! -d "$SEALED_DIR" ]]; then
    echo "Usage: $0 {generate|verify|hash} <sealed-tests-dir>" >&2
    exit 1
fi

compute_hash() {
    find "$SEALED_DIR" -name "*.sh" -print0 | sort -z | \
        while IFS= read -r -d '' f; do shasum -a 256 < "$f"; done | \
        shasum -a 256 | awk '{print $1}'
}

case "${1:-}" in
    generate)
        hash=$(compute_hash)
        echo "$hash" > "$SEALED_DIR/.seal-hash"
        echo "🔐 Seal hash written: ${hash:0:16}..."
        ;;
    verify)
        if [[ ! -f "$SEALED_DIR/.seal-hash" ]]; then
            echo "⚠️  No seal hash found"
            exit 2
        fi
        expected=$(awk '{print $1}' < "$SEALED_DIR/.seal-hash")
        actual=$(compute_hash)
        if [[ "$expected" == "$actual" ]]; then
            echo "🔐 Seal verified"
            exit 0
        else
            echo "🚨 SEAL BROKEN"
            exit 1
        fi
        ;;
    hash)
        compute_hash
        ;;
    *)
        echo "Usage: $0 {generate|verify|hash} <sealed-tests-dir>" >&2
        exit 1
        ;;
esac
