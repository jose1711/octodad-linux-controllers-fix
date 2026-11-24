#!/usr/bin/env bash
# Prepare Octodad: Dadliest Catch (Steam appid 224480, native Linux build) for 4-player co-op
# with more than one gamepad.
#
# The real fix is in the Steam Launch Options (see README.md), this script only
#  1. switches the game to windowed mode (OctodadConfig.xml, UTF-32), because with the newer
#     SDL loaded via SDL_DYNAMIC_API fullscreen stays completely black,
#  2. prints the Launch Options to paste into Steam.
#
# Usage: ./fix.sh [path/to/steamapps/common/Octodad Dadliest Catch]
#        ./fix.sh --restore [path/to/steamapps/common/Octodad Dadliest Catch]
set -euo pipefail

DIR="Octodad Dadliest Catch"
BIN=OctodadDadliestCatch

restore=0
if [[ ${1:-} == --restore ]]; then restore=1; shift; fi

find_game() {
    local vdf p
    for vdf in ~/.local/share/Steam/steamapps/libraryfolders.vdf \
               ~/.steam/steam/steamapps/libraryfolders.vdf \
               ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf; do
        [[ -f $vdf ]] || continue
        while read -r p; do
            [[ -f "$p/steamapps/common/$DIR/$BIN" ]] && { echo "$p/steamapps/common/$DIR"; return; }
        done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' "$vdf")
    done
    return 1
}

game=${1:-$(find_game)} || { echo "Octodad not found, pass the game directory as an argument." >&2; exit 1; }
[[ -f "$game/$BIN" ]] || { echo "Not an Octodad directory: $game" >&2; exit 1; }
cfg=$game/OctodadConfig.xml

if pgrep -f "/$BIN\$" >/dev/null; then
    echo "The game is running, quit it first (it rewrites OctodadConfig.xml on exit)." >&2; exit 1
fi

if (( restore )); then
    if [[ -f $cfg.orig ]]; then
        cp -p "$cfg.orig" "$cfg"; echo "Restored $cfg from $cfg.orig (state before the first ./fix.sh)"
    else
        echo "No $cfg.orig, nothing to restore."
    fi
    echo "Remove the Launch Options in Steam yourself (Octodad -> Properties -> General)."
    exit 0
fi

if [[ -f $cfg ]]; then
    [[ -f $cfg.orig ]] || cp -p "$cfg" "$cfg.orig"      # state before the first run, used by --restore
    bak=$cfg.bak-$(date +%Y%m%d-%H%M%S)
    cp -p "$cfg" "$bak"
    python3 -I - "$cfg" <<'EOF'
import sys, re
path = sys.argv[1]
d = open(path, "rb").read()
# the game writes UTF-32 with BOM; fall back to UTF-16 / UTF-8 just in case
for bom, enc in ((b"\xff\xfe\x00\x00", "utf-32"), (b"\x00\x00\xfe\xff", "utf-32"),
                 (b"\xff\xfe", "utf-16"), (b"\xfe\xff", "utf-16")):
    if d.startswith(bom):
        break
else:
    enc = "utf-8"
s = d.decode(enc)
s2, n = re.subn(r'("Graphics_FullscreenMode"\s+value=")\d+(")', r"\g<1>0\g<2>", s)
if n == 0:
    print("Graphics_FullscreenMode not found in OctodadConfig.xml, not changed.")
elif s2 == s:
    print("Already in windowed mode.")
else:
    open(path, "wb").write(s2.encode(enc))
    print("Switched to windowed mode (Graphics_FullscreenMode=0).")
EOF
    echo "Backup: $bak"
else
    echo "No $cfg yet – start the game once, quit it and run ./fix.sh again."
fi

cat <<'EOT'

Now in Steam:
  1. Octodad -> Properties -> Controller: "Enable Steam Input".
  2. Octodad -> Properties -> General -> Launch Options:

SDL_DYNAMIC_API=/usr/lib/i386-linux-gnu/libSDL2-2.0.so.0 SDL_JOYSTICK_BLACKLIST_DEVICES=0x045e/0x02e0,0x045e/0x028e %command%

     Put the VID/PID of *your* physical pads into SDL_JOYSTICK_BLACKLIST_DEVICES (see README.md),
     so that the game only sees Steam's virtual pads. If the last pad is missing in the game, use
     the variant with "sh -c 'sleep 5; ...'" from README.md.
EOT
