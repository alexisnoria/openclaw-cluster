#!/usr/bin/env bash
# openclaw-cluster.sh — Backward-compatible shim.
#
# The actual implementation now lives in lib/*.sh and the entry point in
# bin/openclaw-cluster. This file exists for backward compatibility with
# existing invocations (`./openclaw-cluster.sh`, `openclaw-cluster.sh start`,
# etc.). For new usage, prefer `bin/openclaw-cluster` directly.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/bin/openclaw-cluster" "$@"
