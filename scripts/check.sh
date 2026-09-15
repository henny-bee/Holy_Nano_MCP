#!/usr/bin/env bash
# Compiles a single .HC file to a scratch binary. Used while iterating.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p build
hcc "$1" -o "build/$(basename "${1%.HC}")"
