#!/usr/bin/env bash
# Behaviour tests for the Window's live reader: tests/window-live.mjs, run under node with the
# machine's config kept out (HOME and CLAUDE_CONFIG_DIR point into a temp dir). TAP output,
# like the other suites; exit 1 on any failure. Needs node 20+.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brigade-window.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/cfg"
export HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/cfg"
if ! command -v node >/dev/null 2>&1; then
  echo "not ok 1 - node is needed for the Window's tests (node 20 or newer)"; echo "# passed 0 · failed 1 · total 1"; exit 1
fi
node "$REPO/tests/window-live.mjs"
