#!/usr/bin/env bash
# SessionStart hook: makes sure the Swift toolchain is installed in Claude Code cloud sessions.
# Does nothing anywhere else (local machines, CI).
set -euo pipefail

if [[ "${CLAUDE_CODE_REMOTE:-}" != "true" ]]; then
    exit 0
fi

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-swift-linux.sh"
