#!/usr/bin/env bash
# Builds the server. Run inside Linux/WSL2 (see docs/PHASE0.md).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/build"
mkdir -p "$OUT"

if ! command -v hcc >/dev/null 2>&1; then
  echo "hcc (holyc-lang compiler) not found - see docs/PHASE0.md" >&2
  exit 1
fi

# hcc compiles a single translation unit; main.HC pulls in every module.
cd "$ROOT"
hcc src/main.HC -o "$OUT/holy-nano-mcp"
echo "built: $OUT/holy-nano-mcp"
