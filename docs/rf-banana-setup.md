# Running RF Banana (RF Online) on macOS via GameBridge

**Status:** Partially working. The free/open-source path is now better than
initially thought: Homebrew Wine Stable 11 gets the launcher (`bananarfo.exe`)
through login, server selection, and into the **Start Game** flow. The current
blocker is later in the launcher-to-game handoff: `RF_Online.bin` starts, but
shows a `Connectioninfo load failure` dialog because it falls back to default
launcher data instead of receiving the real session payload. See
[Session findings](#session-findings) at the bottom for the full checkpoint.

## Game profile

| Field            | Value                                           |
|------------------|-------------------------------------------------|
| Game             | RF Online (RF Banana private server)             |
| Website          | https://rfbanana.com/                            |
| Game binary      | `RF_Online.bin` — **32-bit** (x86) PE, Direct3D 9 |
| Launcher         | `bananarfo.exe` — **64-bit** .NET WPF (RFLauncher namespace, Sirin-backed) |
| Anti-cheat       | Fireguard (`Fireguard/fggm.exe`) — 32-bit .NET, plus Sirin shim in `sirin-launcher.dll` and `d3d9.dll` |
| Audio            | Miles Sound System (`MSS32.DLL`, `mssmp3.asi`)   |
| Graphics API     | Direct3D 9                                       |
| Bundled d3d9.dll | 32-bit, ~22 MB — Sirin anti-tamper shim that wraps D3D9 |
| Other deps       | Qt6Core.dll, Newtonsoft.Json.dll, discord_game_sdk.dll, d3dx9_32/34/36.dll |

## Prerequisites

- macOS 14+ on Apple Silicon (tested on macOS 26.6 Tahoe)
- A Wine binary with 32-bit (WoW64) support and .NET / WPF coverage:
  - **Homebrew Wine Stable 11** — current best free path; launcher works far
    enough to log in, select a server, and spawn the game
  - **gcenx prebuilt GPTK cask** — fast install, works on Tahoe, but Wine 7.7
    so .NET / WPF support is limited
  - **CrossOver 26** (paid) — newer Wine with better .NET / WPF coverage, but
    no longer the first recommendation while the free Wine 11 path is alive
  - **Apple's official GPTK from source** — broken on Tahoe due to
    `openssl@1.1` build failure with the modern Xcode toolchain. Don't bother.
- GameBridge built and running

## Recommended free Wine path

Install current Wine Stable from Homebrew if it is not already present:

```bash
brew install --cask --no-quarantine wine-stable
```

On the test machine this provides `/opt/homebrew/bin/wine`, which reports
Wine 11.x and has materially better WPF/.NET behaviour than GPTK 7.7.

## Installing GPTK (gcenx prebuilt cask)

This is the fastest free path. Requires x86_64 Homebrew installed at
`/usr/local/`:

```bash
arch -x86_64 /usr/local/bin/brew install --cask gcenx/wine/game-porting-toolkit
```

That drops `Game Porting Toolkit.app` into `/Applications` and symlinks
`wine64`, `wineserver`, `wine64-preloader` into `/usr/local/bin/`. GameBridge's
`WineLocator` finds both the app-bundle and `/usr/local/bin/wine64` paths.

## Quick start (one-click)

After the initial setup below has been done once, you can launch end-to-end
with a single double-click:

```
scripts/launch-rfbanana.command
```

It starts the handoff patcher with `--account ArcadeAssassin`, launches
`bananarfo.exe` under Wine 11 in `prefix-wine11`, and cleans up everything
on exit. Edit the `USER CONFIG` block at the top of the script (or override
via `RFB_ACCOUNT=foo RFB_GAME_DIR=/path scripts/launch-rfbanana.command`)
if your paths or account differ from the defaults.

You can also drag the `.command` file to the Dock for a true one-click
launch.

## Step-by-step setup

### 1. Create a bottle

In GameBridge, click `+` to create a new bottle. Name it something like
"RF Banana".

### 2. Initialise the bottle

Select the bottle, pick the GPTK wine64 in the dropdown, then click
**Initialise**. This runs `wineboot --init`.

Expect to see harmless errors during init:
- `err:setupapi:SetupDefaultQueueCallbackW copy error 1812` — wineusb driver
  noise, ignore
- `err:mscoree:LoadLibraryShim error reading registry key for installroot` —
  mscoree probing for .NET runtime location, ignore

### 3. Install D3DMetal

Click **Install D3DMetal** in GameBridge. This copies Apple's Metal-backed
D3D9/11/12 DLLs from your GPTK install into the bottle. Required for the
D3DMetal graphics backend to work.

### 4. Disable WPF hardware acceleration (required for the launcher)

The launcher is WPF-based and hits a known Wine bug when WPF tries to use D3D
for compositing. Run this once after initialising the bottle:

```bash
WINEPREFIX=/path/to/bottle/prefix wine64 reg add "HKCU\Software\Microsoft\Avalon.Graphics" /v DisableHWAcceleration /t REG_DWORD /d 1 /f
```

(Replace `/path/to/bottle/prefix` with the bottle's actual prefix path —
visible in the bottle detail header in GameBridge.)

**Note:** This alone is NOT enough to get the launcher working — see [Session findings](#session-findings).
Real Microsoft .NET Framework 4.8 (via winetricks) is needed.

### 5. Wine Mono — already bundled with GPTK

GPTK ships `wine-mono-7.4.1` at
`Game Porting Toolkit.app/Contents/Resources/wine/share/wine/mono/`. Wine
auto-loads it at runtime — no install needed. The `mscoree` errors during
`wineboot --init` are harmless; Mono is still discoverable via Wine's runtime
lookup.

**Caveat:** Wine Mono's WPF implementation is incomplete. WPF apps (like the
RF Banana launcher) crash in `MS.Win32.UnsafeNativeMethods.GetParent` because
Mono's WPF doesn't correctly interact with Wine's window manager. To get a WPF
launcher actually working, you need real Microsoft .NET Framework 4.8
installed via winetricks (see [Session findings](#session-findings)).

### 6. The bundled d3d9.dll — leave it alone

The game ships its own `d3d9.dll` (~22 MB). This is the Sirin anti-tamper
shim. The game **will not run without it** — we confirmed direct
`RF_Online.bin` launch silently exits because Sirin doesn't get a valid
session.

GameBridge's D3DMetal backend already sets `WINEDLLOVERRIDES=d3d9...=n,b`
("native then builtin"), which lets the bundled DLL load first and forward
calls to Wine's D3D9.

### 7. Launch

**Always launch via `bananarfo.exe`**, never `RF_Online.bin` directly. The
engine requires session tokens that only the launcher can provide.

In GameBridge you can either save `bananarfo.exe` as a shortcut for one-click
launching or use **Run .exe...** for a one-off launcher run.

### 8. Graphics settings

The game defaults to 1366×768 (set in `R3Engine.ini`). You can edit this file
before launching to change resolution:

```ini
[RenderState]
ScreenXSize=1920
ScreenYSize=1080
```

## GameBridge assisted launch capture mode

If you launch `bananarfo.exe` from GameBridge, either from a saved shortcut or
through **Run .exe...**, GameBridge detects the RF Banana layout and starts its
bundled `rfbanana_handoff_patcher.py` helper in capture-only mode before Wine
starts the launcher.

What this does:

- writes `DefaultSet.tmp` snapshots into the bottle's
  `Diagnostics/RFBanana/<timestamp>/` directory
- streams helper output into the GameBridge log alongside Wine output
- makes failed launcher-to-game handoff runs easier to compare later

What this does not do:

- it does not fix `Diff Nation Code`
- it does not replace the native Sirin session handoff
- it is still diagnostic capture only, not a gameplay or login fix

**Current practical answer:** yes, there is now a one-click path for this
inside GameBridge. Save `bananarfo.exe` as a shortcut once, then launch that
saved shortcut entry from the RF Banana bottle view in the GameBridge app.
Do **not** double-click `/Users/argie/Downloads/RF_Banana/bananarfo.exe`
directly in Finder; that bypasses the assisted-launch flow. GameBridge will
automatically apply the RF Banana assisted capture logic on later launches.

## Recommended GameBridge settings

| Setting           | Value                                    |
|-------------------|------------------------------------------|
| Graphics backend  | D3DMetal                                  |
| MetalFX upscaling | ON                                        |
| FPS overlay       | ON (useful for debugging performance)     |
| Advertise AVX     | ON (default, leave it)                    |

## Session findings

This section documents what we actually verified during a hands-on test
session (2026-06-27) so future attempts don't re-derive the same dead ends.

### ✅ What worked

- gcenx GPTK cask install — still useful for D3DMetal bits and bottle setup
- `wineboot --init` against both GPTK Wine 7.7 and Homebrew Wine 11 — both
  initialised cleanly
- GameBridge assisted launch — confirmed on 2026-06-27 with a saved
  `bananarfo.exe` shortcut; helper started automatically, selected Homebrew
  Wine 11 launched the launcher, and a real diagnostics run directory was
  created under `prefix-wine11/Diagnostics/RFBanana/<timestamp>/`
- Homebrew Wine Stable 11 (`/opt/homebrew/bin/wine`) — launcher reaches login,
  server selection, settings, and **Start Game**
- 32-bit WoW64 — `RF_Online.bin` (32-bit PE) launches from a 64-bit Wine 11
  prefix without issue
- Launcher-to-server TCP reachability — verified live to
  `15.235.215.137:10001` and `15.235.215.137:27780`

### ❌ What is still broken

**GPTK Wine 7.7 (`/usr/local/bin/wine64`):**
```
Unhandled Exception:
System.ComponentModel.Win32Exception (0x80004005): mono-io-layer-error (-973058432)
  at MS.Win32.UnsafeNativeMethods.GetParent
  at System.Windows.Interop.HwndTarget.UpdateWindowPos
  at System.Windows.Window.Show
  at RFLauncher.App.OnStartup
```

Wine Mono on GPTK 7.7 is not enough for this launcher. Even after attempting
`winetricks dotnet48`, the prefix ended up in a worse mixed state and the
launcher failed later with:

```
System.TypeLoadException: Could not load type
'System.Runtime.CompilerServices.IAsyncStateMachine'
```

So GPTK 7.7 is a dead end for RF Banana's launcher path.

**Wine 11 launcher-to-game handoff:**
- All servers show `999ms` ping in the launcher UI, but this does **not** mean
  the server is down
- Wine logs repeated `WSASocketW Failed to create a socket of type SOCK_RAW`
  errors, which likely breaks the launcher's ICMP/raw-socket ping probe
- Despite the `999ms` display, direct TCP connection checks to the live login
  and zone ports succeed
- After clicking **Start Game**, the launcher does spawn `RF_Online.bin`, but
  the game shows `Connectioninfo load failure`

`NetLog/rfclient.log` from the failing game run shows:

```text
GetDataFromLauncher
Default CCR Launcher Data Load
SetAccountID UserAccount ^^ UserAccount
[19258 Server]ServerIP = -1982338289, ServerPort = 27780
NationCode = 13015
Diff Nation Code
```

This is the key clue: the game is not failing on first-hop network
reachability. It is failing because it falls back to a default launcher data
path instead of receiving the real session data from the launcher.

### Handoff artifacts identified

- `System/DefaultSet.tmp` — 55-byte binary file, updated immediately before
  `RF_Online.bin` starts. Mirrors `System/DefaultSet.tmt` (same size, original
  template from 2014). Acts as the session handoff blob the game decodes on
  startup.
- `settings.ini` — launcher-selected server and language (`Server=FRESH_ASIA_BEST`,
  `ServerGroup=111`, `LanguageCode=englang`).
- `temp/mainpath.cache` — server-group metadata with resolved hostnames; clear
  text (e.g. `FRESH_ASIA_BEST | 15.235.215.137`).
- `Launcher/users.lst` — account state (UTF-8 with BOM):
  `ArcadeAssassin|QjNCMEFEOTg5...` (account name + base64-encoded password hash).

`RF_Online.bin` contains strings for:
- `Connectioninfo load failure.`
- `GetDataFromLauncher`
- `.\System\DefaultSet.tmp`
- `Default CCR Launcher Data Load`
- `invalid connection information, connection fail.`
- IPC primitive imports: `CreateFileMappingA/W`, `MapViewOfFile`, `OpenEventA/W`,
  `CreateEventA/W` — game has shared-memory IPC code paths

`bananarfo.exe` (64-bit .NET) imports explicit Sirin handoff functions from
`sirin-launcher.dll`:
- `Sirin_LoginA/W`, `Sirin_Logout`
- `Sirin_SetNation`
- `Sirin_SetLoginIP` / `Sirin_SetLoginPort` / `Sirin_SetLoginAddrA/W`
- `Sirin_SetZoneIP` / `Sirin_SetZonePort` / `Sirin_SetZoneAddrA/W`
- `Sirin_EnterWorld`, `Sirin_SecondFactorConfirm`, `Sirin_Panic`

`sirin-launcher.dll` is 64-bit and **imports `WS2_32.dll`** — it makes its own
encrypted network calls to the Sirin auth backend. All other strings (IPC
names, format constants) are obfuscated/packed.

### Refined diagnosis (what `DefaultSet.tmp` proves)

A hex dump of the post-launcher `DefaultSet.tmp` from the failed 06:29 run:

```
00000000: 35 a0 4b 42 32 23 55 73 65 72 41 63 63 6f 75 6e  5.KB2#UserAccoun
00000010: 74 00 00 1e 88 bb 54 2b c1 49 b8 a1 45 bc 53 96  t.....T+.I..E.S.
00000020: 4f bd 67 c4 9a 33 c9 3a 4b 8b 70 42 f2 3b 18 9c  O.g..3.:K.pB.;..
00000030: c8 3a 28 9c d2 d1 32                             .:(...2
```

**`.tmt` (template, 2014) vs `.tmp` (post-launcher) byte diff:** of 55 bytes,
54 differ. Only **offset 19 (`0x1E`)** is identical between the two files.
Conclusion: `.tmt` is not a substitution template — it's a separate
encrypted/binary format. The launcher writes `.tmp` fresh from its own
internal layout each launch.

**Number sanity check — what the game logged vs what the file actually says:**

| Game log               | Decimal      | As LE int32 hex | Bytes (LE)     | Interpretation                       |
|------------------------|--------------|-----------------|----------------|--------------------------------------|
| `ServerIP = -1982338289` | -1982338289 | `0x89D7EB0F`    | `0F EB D7 89`  | **= `15.235.215.137`** (real FRESH_ASIA_BEST IP, correct!) |
| `ServerPort = 27780`   | 27780        | `0x00006C84`    | `84 6C 00 00`  | **= real zone port, correct**         |
| `AccountID = UserAccount` | string    | n/a             | offset 5–16    | **template placeholder, not real account `ArcadeAssassin`** |
| `NationCode = 13015`   | 13015        | `0x000032D7`    | `D7 32 00 00`  | **mismatched** → `Diff Nation Code`  |
| `[19258 Server]` tag   | 19258        | `0x00004B3A`    | `3A 4B 00 00`  | found in `.tmp` at offset 39 (plaintext LE16) |

**This flips the diagnosis.** The launcher IS writing the correct ServerIP and
ServerPort to the handoff blob — the "garbage-looking" negative int in the
game log is just `15.235.215.137` reinterpreted as a signed little-endian
int32. The only fields still wrong are:

- **`AccountID`** — stays at the literal placeholder string `UserAccount`
  instead of being substituted with the real account `ArcadeAssassin` from
  `users.lst`
- **`NationCode`** — `13015` doesn't match what the server expects for this
  account → game refuses with `Diff Nation Code`

The supporting evidence that auth itself succeeds:
- `bananarfo.exe` establishes a live TCP session to `15.235.215.137:10001`
- live HTTPS sessions to `rfbanana.b-cdn.net` (`156.59.126.78:443`)
- `SirinAPI.handleLoginResponse()` only raises `OnLoggedIn` on a native Sirin
  success callback — the logged-in state is real, not UI cache

So the actual bug is narrower than "Sirin auth fails" or "handoff is empty":
the launcher's **account-name and nation-code substitution into the handoff
blob silently no-ops on Wine**. Server IP/port substitution works; account
substitution doesn't.

### Handoff trace proof

An instrumented Wine 11 run with
`WINEDEBUG=+timestamp,+pid,+tid,+process,+file,+sync` captured the exact order
of operations:

1. `bananarfo.exe` opens `.\System\DefaultSet.tmp` for write
2. `bananarfo.exe` launches `.\RF_Online.bin`
3. `RF_Online.bin` opens `.\System\DefaultSet.tmp` for read

Relevant trace lines:

```text
CreateFileW L".\\System\\DefaultSet.tmp" GENERIC_WRITE
CreateProcessInternalW app L".\\RF_Online.bin"
CreateFileW L".\\System\\DefaultSet.tmp" GENERIC_READ
```

This is the missing boundary proof: `DefaultSet.tmp` is the real handoff
artifact. For this title, the launcher-to-game path is file-based.

Repeated failed launches also showed:

- the 55-byte blob changes between runs
- the embedded `UserAccount` placeholder string does not
- the mutable bytes are clustered in the middle of the file

That pattern looks more like a partially-populated session blob than a fully
static template.

### Empirical patch experiment (2026-06-27, Wine 11 + prefix-wine11)

Ran the patcher in active mode against a live launcher session and verified
how much of the game's behaviour `DefaultSet.tmp` controls.

**Setup:**
- Wine 11 from `brew install --cask wine-stable`
- Dedicated prefix `/Users/argie/tmp/gamebridge-rfbanana-lab/prefix-wine11`
- Real logged-in launcher session, account `ArcadeAssassin` (Cora nation)
- Patcher polling `.tmp` at 50 ms, capturing + patching before game read

**Captured 3 successive `.tmp` writes from the same login (08:46, 08:47, 08:48):**

| Offsets | Bytes (first capture)                                | Behaviour                |
|---------|------------------------------------------------------|--------------------------|
| 0–5     | `35 a0 4b 42 32 23`                                   | static across all runs (header + `2#` separator) |
| 6–16    | `55 73 65 72 41 63 63 6f 75 6e 74` = `UserAccount`    | static placeholder; only field that's actually patchable |
| 17–22   | `00 00 1e 88 bb 54`                                   | static across all runs |
| 23–38   | random 16 bytes — different every write               | per-click session nonce |
| 39–54   | `3a 4b 8b 70 42 f2 3b 18 9c c8 3a 28 9c d2 d1 32`     | static across all runs |

**Patches applied + game responses:**

| Patch                                       | Game-log `SetAccountID`   | Game-log everything-else  |
|---------------------------------------------|---------------------------|---------------------------|
| (no patch)                                  | `UserAccount ^^ UserAccount` | constants (see below)     |
| `--account ArcadeAssassin`                  | **`ArcadeAssas ^^ ArcadeAssas`** | unchanged constants  |
| `--account ArcadeAssassin --patch 53=0200`  | `ArcadeAssas ^^ ArcadeAssas` | unchanged constants — patch had NO effect on NationCode |

**The "constants" are identical every single run regardless of patches:**
```
[19258 Server]ServerIP = -1982338289, ServerPort = 27780
Premium = -929294278
Adult = -761518021
NationCode = 13015
Diff Nation Code
```

`ServerIP -1982338289` decodes to `15.235.215.137` (real FRESH_ASIA_BEST IP)
when reinterpreted as little-endian int32, but **these values are not coming
from `.tmp`** — they're hardcoded sentinels that the game's "Default CCR
Launcher Data Load" code path emits when the real IPC fails. Proved by:
- Patching bytes 53-54 (a candidate NationCode location) didn't change the
  game's `NationCode = 13015` output
- The hex bytes that would encode any of the logged values are not present
  in `.tmp` at the obvious offsets

**Wine `+file +process` trace around the handoff (from prior session):**
```
39233.181  launcher writes DefaultSet.tmp (55 bytes)
39233.184  launcher spawns RF_Online.bin (cmdline=null — no argv handoff)
39233.494  game opens NetLog/rfclient.log
39233.503  game reads R3Engine.ini (Language=Philippines)
39233.504  game reads DefaultSet.tmp
```

No other shared file, no command-line arguments. `RF_Online.bin` is launched
with `cmdline=null`. The `+file +process` channels would not catch named
shared memory or events; that channel coverage would need `+ntdll +sync`
or similar.

**Conclusion:** `DefaultSet.tmp` is the *fallback* handoff channel, not the
primary one. It carries exactly two pieces of information: the AccountID
(11-byte plaintext at offset 6) and a per-click 16-byte nonce. Everything
else the game prints — server IP, port, premium, adult, NationCode — comes
from hardcoded fallback sentinels emitted on the "Default CCR Launcher
Data Load" code path. The real session payload moves over some IPC the
launcher's obfuscated `sirin-launcher.dll` sets up (almost certainly named
shared memory via `CreateFileMapping` + `OpenEvent`, given the game's
import list), and **that IPC silently fails under Wine 11** — putting the
game on the degraded fallback path.

To actually get the game playable from here, the work isn't on `.tmp`
contents anymore. It's:
1. Trace launcher with `WINEDEBUG=+ntdll,+sync,+seh` (not `+file`) to see
   the `NtCreateSection` / `NtOpenSection` / `NtCreateEvent` calls Sirin
   makes when assembling the IPC.
2. Diff Wine 11's named-object behaviour against what real Windows does for
   a cross-bitness (64-bit launcher → 32-bit game) shared mapping — that
   WoW64 cross-bitness scenario is a known sharp edge in older Wine and may
   well be the proximate cause.
3. Failing all of the above, write a small native 32-bit helper that
   creates the expected `RF_CLIENT`/`RF_ONLINE` mapping ourselves with the
   real session values and let `RF_Online.bin` find that instead.

### Wine `+winsock,+server,+process` trace (2026-06-27, post-Start-Game click)

Captured the launcher's behaviour from start through Start Game click with
the right debug channels to actually see kernel-object and network ops.

**Named kernel-object primitives:** Filtered the `+server` log for every
`create_mapping`, `create_event`, `create_mutex` with a non-empty name.
Only matches were Wine internals (loading kernel32.dll, `__wine_clipboard_*`,
`__WINE_FUSION_CACHE_MUTEX__`, etc.) and OS boilerplate (`Z:\Users\...\inetcache!`).
**Zero RF/CCR/Sirin-specific named objects.** The launcher does NOT use named
shared memory, events, or mutexes for IPC with the game. Rules out the
"CreateFileMapping" theory.

**Localhost sockets:** Launcher does bind/listen on `127.0.0.1:51334`, but it
also issues the matching `connect()` itself and accepts its own connection.
Both ends of the loopback live in the launcher process; this is internal
thread-sync, not the game IPC channel.

**Process spawn:** `CreateProcessInternalW app L".\\RF_Online.bin" cmdline (null)`.
No command-line arguments, no `SetHandleInformation` calls, no special
environment variables set near the spawn. Pid 02bc, handles 0x570/0x574 —
those are stdin/stdout pipes for Wine, not session data.

**Game-side imports:** Verified by parsing the PE32 import tables of all
three relevant binaries:

| Binary               | Arch  | Network libs imported          |
|----------------------|-------|--------------------------------|
| `bananarfo.exe`      | x64   | (managed; via sirin-launcher)  |
| `sirin-launcher.dll` | x64   | `WS2_32.dll`                   |
| **`d3d9.dll`** (bundled, 22 MB) | **x86** | **`WS2_32.dll`** |
| `RF_Online.bin`      | x86   | `WS2_32`, `WININET`, `iphlpapi` |

**The bundled 32-bit `d3d9.dll` is NOT a graphics wrapper** — it's a Sirin
network client masquerading as a D3D9 proxy. The game loads it during init,
and the trace shows it doing extensive socket activity from TID 02cc (game
worker), including `connect()` to `94.249.192.52:443` (Sirin auth backend),
followed by successful `WS2_sendto`/`WS2_recv_base` cycles on the same
socket.

**Important: `STATUS_DEVICE_NOT_CONNECTED` (`0xC00000A3`) returned by
`connect()` is NOT a real failure here.** The socket was put in non-blocking
mode via `FIONBIO` immediately before connecting, so `0xC00000A3` is just
`EINPROGRESS` / `STATUS_PENDING`. The subsequent successful sends and recvs
on the same socket confirm the TCP connection completed asynchronously.

**Where the trail goes cold:** Game-side network activity happens AFTER
the game's `rfclient.log` already logs "Default CCR Launcher Data Load". So
the game decides to use defaults BEFORE its Sirin network call. Either:
1. The game's network activity is anti-cheat telemetry, not session retrieval.
2. The session-retrieval code path is in an earlier step that we haven't
   located — possibly inside the obfuscated `d3d9.dll` reading something
   from the launcher's process state (PEB, inherited handles, registry).

**To get further, the investigation needs:**
- Ghidra/IDA on the bundled 32-bit `d3d9.dll` to find what it does between
  `DllMain` and the "Default CCR Launcher Data Load" log line. That's the
  function that decides "I have valid session data" vs "fall back to defaults".
- OR a Wine MitM proxy (e.g. setting `WINE_HTTPS_PROXY` and routing through
  mitmproxy) to capture the actual TLS payloads to `94.249.192.52` and
  understand what data the launcher's `Sirin_EnterWorld` exchanges with the
  Sirin backend — and what response shape would be considered "valid".

### Dead ends not worth retrying

- **Apple's official GPTK via `brew install apple/apple/game-porting-toolkit`**
  — broken on macOS 26 Tahoe. Hits a chain of issues:
  1. `openssl@1.1` removed from homebrew/core (workaround: extract from
     historical commit)
  2. Extracted formula has `disable!` directive (workaround: edit out)
  3. Filename / class name mismatch (workaround: rename)
  4. Build fails: `clang: error: unsupported argument 'westmere' to option '-march='`
     — Xcode 17 dropped that arch flag, no clean workaround
- **Disabling WPF hardware acceleration via registry** — does not fix the
  `GetParent` crash. The crash is in window manager interop, not in WPF's
  rendering path.
- **Treating `999ms` as proof the server is unreachable** — false signal.
  Under Wine 11 the raw-socket ping path is broken, but TCP connectivity to
  the live server is fine.

### The realistic path forward

The bug is now narrowed to a specific substitution failure: server IP/port get
populated correctly in `DefaultSet.tmp`, but account name and nation code
stay at template defaults.

Concrete next steps:

1. **Capture a second `DefaultSet.tmp` from another launch and diff it
   against the first.**
   ```bash
   # First run blob:
   cp /Users/argie/Downloads/RF_Banana/System/DefaultSet.tmp /tmp/dst-run1.bin
   # Run the launcher, log in, Start Game (let it fail again), exit.
   cp /Users/argie/Downloads/RF_Banana/System/DefaultSet.tmp /tmp/dst-run2.bin
   cmp -l /tmp/dst-run1.bin /tmp/dst-run2.bin
   ```
   - Bytes that **differ** = per-session nonce/token (variable each launch).
   - Bytes that **stay identical** = "identity" fields the launcher should be
     populating from persistent state (account name, nation code, etc.).
   - The literal `UserAccount` plaintext should stay identical → confirms the
     account substitution is silently no-opping rather than writing random
     garbage.

2. **Test whether the blob can be patched between launcher write and game read.**
   See [`scripts/rfbanana_handoff_patcher.py`](../scripts/rfbanana_handoff_patcher.py).
   It polls `System/DefaultSet.tmp` every 50 ms, snapshots every write to
   `/tmp` (timestamped, for diffing), prints a compact byte-diff vs the
   previous snapshot, and applies any patch directives before the game
   reads the file. Run BEFORE clicking Start Game:
   ```bash
   # Capture only (collect snapshots, no modification):
   python3 scripts/rfbanana_handoff_patcher.py \
     --game-dir /Users/argie/Downloads/RF_Banana \
     --no-patch

   # Patch the account name (offset 6, 11 bytes max):
   python3 scripts/rfbanana_handoff_patcher.py \
     --game-dir /Users/argie/Downloads/RF_Banana \
     --account ArcadeAssassin

   # Patch account + arbitrary bytes (e.g. testing nation byte at offset 50):
   python3 scripts/rfbanana_handoff_patcher.py \
     --game-dir /Users/argie/Downloads/RF_Banana \
     --account ArcadeAssassin \
     --patch 50=01 --patch 0x32=ff
   ```
   `--patch OFFSET=HEXBYTES` accepts decimal or `0x..` offsets and any
   even-length hex string. Multiple `--patch` flags compose. Errors out
   if a patch overruns the 55-byte blob.

   If the game's `Diff Nation Code` error shifts to something else after a
   patched run, we've confirmed the substitution bug — capture the new
   error and use the diff output between successive snapshots to triangulate
   the next field to patch.

   **Layout observed so far** (offsets in `DefaultSet.tmp`):
   - `0-3`: 4-byte header / magic (varies per run)
   - `4`:   `0x32` (`'2'`) — possible field-type tag
   - `5`:   `0x23` (`'#'`) — separator
   - `6-16`: account-name string (11 ASCII bytes, the stuck `UserAccount`)
   - `17`:  `0x00` — terminator
   - `18`:  `0x00` — padding
   - `19`:  `0x1E` — constant record-separator (identical in `.tmt`)
   - `20+`: encrypted/binary session payload (server IP/port land here)

3. **(Done — see "IL analysis" below.)** `bananarfo.exe` does NOT write
   `DefaultSet.tmp` itself. All it does is pass values to native
   `sirin-launcher.dll` via P/Invoke and call `Sirin_EnterWorld(0, 0)`. The
   native DLL writes the blob.

4. **Trace `sirin-launcher.dll` around `Sirin_EnterWorld`.**
   This is now the only code path left that can produce the bug. The native
   DLL is obfuscated/packed (imports kernel32 and WS2_32 but all string
   constants encrypted). Needs a debugger (Ghidra/IDA + Wine-side breakpoints)
   to trace where the username from `Sirin_LoginA` and the nation from
   `Sirin_SetNation` get serialized.

5. **Keep Wine 11 as the primary path.**
   CrossOver may help as a comparison point later, but the path is close
   enough that finishing the handoff investigation here makes sense first.

### IL analysis of `bananarfo.exe` (definitive)

`bananarfo.exe` decompiled via `ikdasm` (bundled with `brew install mono`).
The relevant managed code paths are short and unambiguous:

**`SirinAPI::login(username, password)`** (line 1561 of the IL dump):
```il
IL_0002: call void RFLauncher.SirinWrapper::Sirin_LoginA(string, string)
IL_0007: ldsfld   class RFLauncher.utility.UserData RFLauncher.SirinAPI::userData
IL_000d: callvirt instance void RFLauncher.utility.UserData::set_Username(string)
```
Calls the native `Sirin_LoginA(pszLogin, pszPassword)` with the user's input,
then stores the username in a *managed* `UserData.Username` property for UI
display. The native DLL gets the username via `Sirin_LoginA` only.

**`SirinAPI::configureSirin()`** (the pre-launch setup, line 1635 of IL):
```il
// SirinIP from the selected server item:
IL_002c: callvirt instance string RFLauncher.controls.ServerItem::get_SirinIP()
IL_0032: call     void RFLauncher.SirinWrapper::Sirin_SetLoginAddrA(string)
IL_0038: call     void RFLauncher.SirinWrapper::Sirin_SetLoginAddrW(string)
IL_003d: ldc.i4   0x2711                      // = 10001, HARDCODED login port
IL_0042: call     void RFLauncher.SirinWrapper::Sirin_SetLoginPort(uint16)
IL_0048: call     void RFLauncher.SirinWrapper::Sirin_SetZoneAddrA(string)
IL_004d: call     void RFLauncher.SirinWrapper::Sirin_SetZoneAddrW(string)
IL_0052: ldc.i4   0x6c84                      // = 27780, HARDCODED zone port
IL_0057: call     void RFLauncher.SirinWrapper::Sirin_SetZonePort(uint16)
IL_005c: call     class RFLauncher.Properties.Settings::get_Default()
IL_0061: callvirt instance uint8 RFLauncher.Properties.Settings::get_ClientLevel()
IL_0066: call     void RFLauncher.SirinWrapper::Sirin_SetNation(uint8)
```

**`SirinAPI::launch()`** (called from `StartGameAsync`, line 1581):
```il
IL_0000: ldc.i4.0
IL_0001: ldc.i4.0
IL_0002: call void RFLauncher.SirinWrapper::Sirin_EnterWorld(bool, bool)
```

That's it. `bananarfo.exe` never opens or writes `DefaultSet.tmp`. It only
P/Invokes into `sirin-launcher.dll`. So:

| Value the game reads        | Comes from (managed)                   | Native call                 |
|------------------------------|----------------------------------------|-----------------------------|
| ServerIP / ZoneIP            | `ServerSelected.SirinIP`               | `Sirin_SetLoginAddrA/W` + `Sirin_SetZoneAddrA/W` |
| Login port (10001)           | hardcoded `0x2711` IL constant         | `Sirin_SetLoginPort`        |
| Zone port (27780)            | hardcoded `0x6c84` IL constant         | `Sirin_SetZonePort`         |
| AccountID                    | user's text input to login control     | `Sirin_LoginA(pszLogin, ...)` |
| NationCode                   | `Settings.Default["ClientLevel"]` (`uint8`) | `Sirin_SetNation(uint8)` |
| Everything else (session token, encryption nonce, etc.) | Sirin internal state | native only |

**`ClientLevel` is read from .NET `Settings.Default["ClientLevel"]`** — an
application-settings property, persisted in `user.config` under the user's
local app-data directory. On Wine, that path resolves via
`Environment.SpecialFolder.LocalApplicationData`. If the user.config doesn't
exist or the key isn't set, `Settings.Default` returns the type's default
(0 for `Byte`). That would explain why `NationCode = 13015` (clearly garbage
relative to what the server expects) — the launcher is sending nation `0` and
the native DLL is composing a NationCode field from that plus stale memory.

For the AccountID staying `UserAccount`: the username DOES flow correctly
through managed code to `Sirin_LoginA`. The only place it can be lost is
inside the native `sirin-launcher.dll`'s storage of the login name, or in
its later write of that name into `DefaultSet.tmp`. The native DLL is
obfuscated, so confirming this requires a runtime debugger.

**Practical implication:** the workaround in `rfbanana_handoff_patcher.py`
(patch account name at offset 6) is well-targeted. The next extension
should also patch the NationCode byte — once we identify which byte it is
by diffing two `.tmp` blobs with different `ClientLevel` settings.

### Known risks (carried over, not yet verified)

- **Fireguard anti-cheat** — 32-bit .NET, lightweight, no kernel driver.
  Hasn't been hit yet because the launcher crashed before getting there.
- **Miles Sound System** (`MSS32.DLL`, `mssmp3.asi`) — well-supported by Wine,
  no expected issues.
- **Discord Game SDK** (`discord_game_sdk.dll`) — may fail silently; if it
  causes a crash, rename it away:
  ```
  mv discord_game_sdk.dll discord_game_sdk.dll.bak
  ```
- **Qt6 dependency** (`Qt6Core.dll`) — Qt6 on Wine has known issues; may be
  another wall after WPF is solved.
