#!/usr/bin/env python3
"""
RF Banana DefaultSet.tmp handoff patcher and capture tool.

Wraps a launcher run by watching System/DefaultSet.tmp for writes by
bananarfo.exe. When the launcher writes the handoff blob, this tool:

  1. Snapshots the raw blob to /tmp with a timestamp (for diffing).
  2. Applies any --account substitution AND/OR any --patch directives
     to the snapshot.
  3. Writes the patched blob back to DefaultSet.tmp before RF_Online.bin
     reads it.

The launcher writes the blob then spawns RF_Online.bin within a fraction
of a second, so polling has to be fast. Default poll interval is 50 ms.

Background: ikdasm of bananarfo.exe confirmed the .NET layer never opens
DefaultSet.tmp — it only P/Invokes Sirin_LoginA, Sirin_SetLoginAddrA/W,
Sirin_SetLoginPort(10001), Sirin_SetZoneAddrA/W, Sirin_SetZonePort(27780),
Sirin_SetNation(ClientLevel=6 always), and Sirin_EnterWorld(0,0). The
native obfuscated sirin-launcher.dll writes the blob. On Wine the AccountID
ends up as the literal placeholder 'UserAccount' (offset 6, 11 bytes) and
NationCode renders as 13015. This script lets you patch around the bug.

Usage:
    rfbanana_handoff_patcher.py \\
        --game-dir /Users/argie/Downloads/RF_Banana \\
        --account ArcadeAssassin \\
        [--patch OFFSET=HEXBYTES ...] \\
        [--no-patch]      # capture only, don't modify
        [--out-dir /tmp]  # where snapshots go

Examples:
    # Capture only, no modification (collect blobs for diffing):
    rfbanana_handoff_patcher.py --game-dir ... --account x --no-patch

    # Patch account name + a hypothetical nation byte at offset 50:
    rfbanana_handoff_patcher.py --game-dir ... \\
        --account ArcadeAssassin --patch 50=01

    # Patch raw bytes at multiple offsets:
    rfbanana_handoff_patcher.py --game-dir ... \\
        --account ArcadeAssassin \\
        --patch 40=deadbeef --patch 48=ff

Run this BEFORE clicking 'Start Game' in the launcher. Ctrl-C to stop.
"""

import argparse
import os
import shutil
import sys
import time
from pathlib import Path

# Layout of System/DefaultSet.tmp (55 bytes total, observed):
#   offsets 0-3:  4-byte header / magic (varies per run)
#   offset  4:    literal '2' (0x32) — possibly a field-type tag
#   offset  5:    literal '#' (0x23) — separator
#   offsets 6-16: account-name string (max 11 ASCII chars)
#   offset  17:   '\0' terminator
#   offset  18:   '\0' padding
#   offset  19:   0x1E — constant record-separator, identical in .tmt
#   offsets 20+:  encrypted/binary session payload (server IP/port etc.)
#
# We replace ONLY the 11-byte account-name slot, leaving the prefix and
# terminator intact. Real account names longer than 11 ASCII chars are
# truncated.
ACCOUNT_OFFSET = 6
ACCOUNT_MAX_LEN = 11  # bytes 6..16; offset 17 stays '\0'


def patch_account(blob: bytes, account: str) -> bytes:
    """Replace the account-name field at offset 6-16 with `account`.

    The field is 11 bytes (original 'UserAccount'). Names longer than
    11 ASCII chars are truncated; shorter names are null-padded. The
    '#' separator at offset 5 and the terminator at offset 17 are
    preserved.
    """
    name_bytes = account.encode("ascii", errors="replace")[:ACCOUNT_MAX_LEN]
    name_bytes = name_bytes + b"\x00" * (ACCOUNT_MAX_LEN - len(name_bytes))
    return blob[:ACCOUNT_OFFSET] + name_bytes + blob[ACCOUNT_OFFSET + ACCOUNT_MAX_LEN :]


def parse_patch_spec(spec: str) -> tuple[int, bytes]:
    """Parse a --patch OFFSET=HEXBYTES directive.

    OFFSET is decimal or 0x-prefixed hex. HEXBYTES is an even-length
    hex string with no separators (e.g. 'deadbeef', 'ff', '01').
    """
    if "=" not in spec:
        raise ValueError(f"--patch needs OFFSET=HEXBYTES, got {spec!r}")
    off_s, hex_s = spec.split("=", 1)
    off = int(off_s, 0)
    hex_s = hex_s.strip().replace(" ", "")
    if len(hex_s) % 2 != 0:
        raise ValueError(f"--patch hex needs even length, got {hex_s!r}")
    try:
        data = bytes.fromhex(hex_s)
    except ValueError as e:
        raise ValueError(f"--patch invalid hex {hex_s!r}: {e}")
    return off, data


def apply_patches(blob: bytes, patches: list[tuple[int, bytes]]) -> bytes:
    """Apply a list of (offset, bytes) patches to blob in order."""
    out = bytearray(blob)
    for off, data in patches:
        if off + len(data) > len(out):
            raise ValueError(
                f"patch at offset {off} ({len(data)} bytes) overruns "
                f"{len(out)}-byte blob"
            )
        out[off : off + len(data)] = data
    return bytes(out)


def hex_diff(a: bytes, b: bytes) -> str:
    """Return a compact diff like '6:55->41,7:73->72,...' for changed offsets."""
    if len(a) != len(b):
        return f"length changed: {len(a)} -> {len(b)}"
    diffs = [(i, a[i], b[i]) for i in range(len(a)) if a[i] != b[i]]
    if not diffs:
        return "(no changes)"
    return ", ".join(f"{i}:{x:02x}->{y:02x}" for i, x, y in diffs)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-dir", required=True, type=Path,
                    help="Path to RF_Banana folder (contains System/DefaultSet.tmp)")
    ap.add_argument("--account", default=None,
                    help="Real account name to patch into offset 6-16 "
                         "(omit to leave account field untouched)")
    ap.add_argument("--patch", action="append", default=[], metavar="OFFSET=HEX",
                    help="Patch raw bytes at OFFSET (decimal or 0x..). "
                         "May be passed multiple times. Example: --patch 50=01")
    ap.add_argument("--no-patch", action="store_true",
                    help="Capture snapshots only; don't modify the file")
    ap.add_argument("--out-dir", default="/tmp", type=Path,
                    help="Where to write snapshots (default: /tmp)")
    ap.add_argument("--poll-ms", type=int, default=50,
                    help="Poll interval in milliseconds (default: 50)")
    args = ap.parse_args()

    # Parse --patch directives up front so errors fail fast.
    try:
        raw_patches = [parse_patch_spec(p) for p in args.patch]
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    tmp_path = args.game_dir / "System" / "DefaultSet.tmp"
    if not tmp_path.exists():
        print(f"ERROR: {tmp_path} does not exist (has the launcher ever run?)",
              file=sys.stderr)
        return 1

    args.out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Watching: {tmp_path}")
    print(f"Account:  {args.account if args.account else '(not patching)'}")
    print(f"Patches:  {raw_patches if raw_patches else '(none)'}")
    print(f"Mode:     {'CAPTURE-ONLY' if args.no_patch else 'PATCH'}")
    print(f"Out dir:  {args.out_dir}")
    print()
    print("Now click 'Start Game' in the launcher. Ctrl-C to stop.")
    print()

    last_mtime = tmp_path.stat().st_mtime_ns
    last_blob = tmp_path.read_bytes()
    snapshot_n = 0
    poll_s = args.poll_ms / 1000.0

    try:
        while True:
            time.sleep(poll_s)
            try:
                st = tmp_path.stat()
            except FileNotFoundError:
                continue
            if st.st_mtime_ns == last_mtime:
                continue

            # File changed. Snapshot the raw write before any modification.
            blob = tmp_path.read_bytes()
            ts = time.strftime("%Y%m%d-%H%M%S")
            snapshot_n += 1
            snap_raw = args.out_dir / f"DefaultSet-{ts}-{snapshot_n:02d}-raw.bin"
            snap_raw.write_bytes(blob)
            print(f"[{ts}] write detected ({len(blob)} bytes) -> {snap_raw.name}")

            # Diff against previous snapshot to highlight per-session bytes.
            if last_blob:
                print(f"          diff vs prev: {hex_diff(last_blob, blob)}")
            last_blob = blob

            # Show the account-name region as-written by the launcher.
            name_field = blob[ACCOUNT_OFFSET : ACCOUNT_OFFSET + ACCOUNT_MAX_LEN]
            print(f"          account field (offset {ACCOUNT_OFFSET}-{ACCOUNT_OFFSET+ACCOUNT_MAX_LEN-1}): {name_field!r}")

            if args.no_patch:
                last_mtime = tmp_path.stat().st_mtime_ns
                print()
                continue

            # Build the patched blob: account substitution first, then --patch
            # directives. --patch wins if it overlaps the account region.
            patched = blob
            if args.account:
                patched = patch_account(patched, args.account)
            if raw_patches:
                try:
                    patched = apply_patches(patched, raw_patches)
                except ValueError as e:
                    print(f"          PATCH ERROR: {e}", file=sys.stderr)

            if patched != blob:
                snap_patched = args.out_dir / f"DefaultSet-{ts}-{snapshot_n:02d}-patched.bin"
                snap_patched.write_bytes(patched)
                tmp_path.write_bytes(patched)
                print(f"          PATCHED: {hex_diff(blob, patched)}")
                print(f"          patched copy: {snap_patched.name}")

            last_mtime = tmp_path.stat().st_mtime_ns
            print()

    except KeyboardInterrupt:
        print("\nStopped.")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
