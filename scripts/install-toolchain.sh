#!/usr/bin/env bash
# Installs the holyc-lang compiler (hcc), which this project is built with.
#
# Linux/macOS, or WSL2 on Windows. Needs a C compiler, make, cmake and git.
set -euo pipefail

SRC_DIR="${HOLYC_SRC:-/opt/src/holyc-lang}"
REPO="https://github.com/Jamesbarford/holyc-lang.git"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing build dependency: $1" >&2; exit 1; }; }
need git
need cmake
need make
command -v gcc >/dev/null 2>&1 || need clang

if command -v hcc >/dev/null 2>&1; then
  echo "hcc already installed: $(command -v hcc)"
  hcc --version
  exit 0
fi

mkdir -p "$(dirname "$SRC_DIR")"
if [ -d "$SRC_DIR/.git" ]; then
  git -C "$SRC_DIR" pull --ff-only
else
  git clone --depth 1 "$REPO" "$SRC_DIR"
fi

cd "$SRC_DIR"
make
if [ "$(id -u)" -eq 0 ]; then make install; else sudo make install; fi

hcc --version
echo "hcc installed"
