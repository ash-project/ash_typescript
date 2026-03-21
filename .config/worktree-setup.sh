#!/usr/bin/env bash
set -euo pipefail

echo "==> Syncing dependencies..."
mix deps.get --quiet
(cd test/ts && npm install --silent)

echo ""
echo "==> Worktree ready!"
