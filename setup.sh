#!/usr/bin/env bash
#
# Set up and build flutterbug-terps on a new machine.
# Run from anywhere; clones sibling repos next to this one.
#
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
PARENT_DIR=$(cd "$REPO_DIR/.." && pwd)

clone_or_skip() {
    local dir=$1 url=$2 branch=${3:-}
    if [ -d "$PARENT_DIR/$dir" ]; then
        echo "  $dir already exists, skipping"
    else
        git clone "$url" "$PARENT_DIR/$dir"
        if [ -n "$branch" ]; then
            git -C "$PARENT_DIR/$dir" checkout "$branch"
        fi
    fi
}

echo "=== Cloning sibling repos into $PARENT_DIR ==="
clone_or_skip garglk   https://github.com/garglk/garglk
clone_or_skip remglk-rs https://github.com/joelburton/remglk-rs \
    fix-window-set-arrangement-reentrant-lock
clone_or_skip games    https://github.com/joelburton/flutterbug-terps-games

echo
echo "=== Building ==="
cmake -B "$REPO_DIR/build" -S "$REPO_DIR"
cmake --build "$REPO_DIR/build" -j

echo
echo "=== Testing ==="
"$REPO_DIR/tests/smoke.sh"
