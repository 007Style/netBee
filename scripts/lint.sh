#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# lint.sh  —  Run swift-format and SwiftLint checks (optional, requires tools)
# Usage:  ./scripts/lint.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "🐝 netBee — lint check…"

if command -v swift-format &>/dev/null; then
    swift-format lint --recursive Sources/ Tests/
    echo "✅  swift-format: OK"
else
    echo "⚠️  swift-format not found — skipping (brew install swift-format)"
fi

if command -v swiftlint &>/dev/null; then
    swiftlint lint --quiet
    echo "✅  SwiftLint: OK"
else
    echo "⚠️  SwiftLint not found — skipping (brew install swiftlint)"
fi
