#!/bin/bash
# One-click launcher for RF Banana under Wine 11 + handoff patcher.
#
# Double-click this file (or run it from Terminal) to:
#   1. Start the DefaultSet.tmp handoff patcher in the background,
#      substituting the account name and capturing snapshots.
#   2. Launch bananarfo.exe via Homebrew Wine Stable in the prefix at
#      ~/tmp/gamebridge-rfbanana-lab/prefix-wine11.
#   3. Clean up patcher + wineserver when the launcher exits.
#
# Edit the three variables below if your account, game folder, or prefix
# differ from the defaults.

set -u

# --- USER CONFIG ---
GAME_DIR="${RFB_GAME_DIR:-$HOME/Downloads/RF_Banana}"
ACCOUNT="${RFB_ACCOUNT:-ArcadeAssassin}"
PREFIX="${RFB_PREFIX:-$HOME/tmp/gamebridge-rfbanana-lab/prefix-wine11}"
WINE="${RFB_WINE:-/opt/homebrew/bin/wine}"
CAPTURES_DIR="${RFB_CAPTURES_DIR:-/tmp/rfbanana-captures}"
# -------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHER="$SCRIPT_DIR/rfbanana_handoff_patcher.py"

# Sanity checks
for path in "$GAME_DIR/bananarfo.exe" "$PREFIX/drive_c" "$WINE" "$PATCHER"; do
  if [ ! -e "$path" ]; then
    echo "ERROR: $path not found" >&2
    echo "Edit the USER CONFIG block at the top of $0 to point at your install." >&2
    read -p "Press Enter to close." _
    exit 1
  fi
done

mkdir -p "$CAPTURES_DIR"

# Start the patcher in background
echo ">>> starting handoff patcher (account=$ACCOUNT) -> $CAPTURES_DIR"
python3 -u "$PATCHER" \
  --game-dir "$GAME_DIR" \
  --account "$ACCOUNT" \
  --out-dir "$CAPTURES_DIR" &
PATCHER_PID=$!

# Make sure we clean up on exit (Ctrl-C, launcher close, anything)
cleanup() {
  echo
  echo ">>> shutting down patcher + wineserver..."
  kill -TERM "$PATCHER_PID" 2>/dev/null || true
  pkill -9 -f bananarfo.exe 2>/dev/null || true
  "$WINE"server -k 2>/dev/null || true
  echo ">>> done."
}
trap cleanup EXIT

# Tiny pause so the patcher prints its banner before the launcher noise starts
sleep 1

# Launch the game
echo ">>> launching bananarfo.exe under Wine 11 (prefix=$PREFIX)"
cd "$GAME_DIR"
WINEPREFIX="$PREFIX" WINEDEBUG=-all "$WINE" bananarfo.exe
