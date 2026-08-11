#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# test.sh  —  Run the netBee test suite
# Usage:  ./scripts/test.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

echo "🐝 netBee — running tests…"
swift test --parallel 2>&1

echo ""
echo "✅  All tests passed."
