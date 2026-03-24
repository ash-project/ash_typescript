# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

#!/usr/bin/env bash
set -euo pipefail

echo "==> Syncing dependencies..."
mix deps.get --quiet
(cd test/ts && npm install --silent)

echo ""
echo "==> Worktree ready!"
