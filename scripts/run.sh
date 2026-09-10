#!/bin/bash
# Rebuild, kill any running copy, relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."
"./scripts/build.sh"
pkill -x StickyDock 2>/dev/null || true
sleep 0.4
open "./build/StickyDock.app"
echo "==> launched"
