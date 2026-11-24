# Octodad: Dadliest Catch on Linux – only one gamepad works in co-op

[Slovenská verzia nižšie](#slovensky)

## Symptoms

- [Octodad: Dadliest Catch](https://store.steampowered.com/app/224480/Octodad_Dadliest_Catch/)
  (Steam appid 224480, native Linux build 1.2.19338, buildid 6171554) only sees one gamepad,
  although several are connected – co-op (up to 4 players, one per limb) can't be set up.
- Bluetooth pads (e.g. 8BitDo SN30 Pro in X-input mode) don't work at all on a desktop with
  many input devices.
- With more pads made visible, some of them can lift a leg but not move it, or move it only
  in one axis and in the wrong direction.

## Cause

1. **Old SDL2 linked statically into the game.** The game binary contains its own SDL2
   (built without udev, `JoystickInitWithoutUdev`). It only scans `/dev/input/event0` …
   `event31` and has no hotplug. On a desktop with keyboards, mice, audio jacks, virtual
   devices (ydotool, keymapper, …) these 32 slots are taken, newer pads get `event256+` and
   the game never sees them.

   The static SDL is built with the *dynamic API* (`SDL_DYNAMIC_API`), so it can be redirected
   to a newer SDL2 without touching any game file: the Steam Linux Runtime has SDL 2.32 at
   `/usr/lib/i386-linux-gnu/libSDL2-2.0.so.0` (path inside the container).

2. **The game reads raw joystick axes.** On Linux the game's gamepad layer is an empty stub;
   it uses the *Joystick* entries of `InputRemapping14-01-15.xml` with raw axis numbers in the
   Xbox 360 order (`X,Y` left stick, `Z` LT, `R,U` right stick, `V` RT). Pads with a different
   axis order break: an 8BitDo via SDL's HIDAPI driver has `Z,R` = right stick and `U` = LT,
   so the right leg lifts (RT is `V` on both) but moves only in one axis, inverted.

   **Steam Input** solves this: every pad becomes a virtual Xbox 360 pad (`28de:11ff`, "Microsoft
   X-Box 360 pad N") with exactly that axis order. The physical pads then have to be hidden from
   the game, otherwise each pad is seen twice.

3. **No hotplug.** Steam creates the virtual pads when the game starts, the last one can appear
   a second or two later – the game doesn't see it. Delaying the game start fixes it.

4. **Black screen in fullscreen.** With SDL 2.32 the fullscreen window stays completely black
   (tested on GNOME/Xwayland, multi-monitor). Windowed mode works.

## Fix

1. Run the script (switches the game to windowed mode, with backups; prints the Launch Options):

   ```sh
   git clone https://github.com/jose1711/octodad-linux-controllers-fix
   cd octodad-linux-controllers-fix
   ./fix.sh                    # auto-detects the game in your Steam libraries
   ./fix.sh "/path/to/steamapps/common/Octodad Dadliest Catch"
   ./fix.sh --restore          # put back OctodadConfig.xml from before the first run
   ```

   Or by hand: in `OctodadConfig.xml` set `Graphics_FullscreenMode` to `0`. The file is
   **UTF-32**, `sed` won't match, use an editor that understands it (or the script).

2. Steam → Octodad → Properties → **Controller: Enable Steam Input**.

3. Steam → Octodad → Properties → General → **Launch Options**:

   ```
   SDL_DYNAMIC_API=/usr/lib/i386-linux-gnu/libSDL2-2.0.so.0 SDL_JOYSTICK_BLACKLIST_DEVICES=0x045e/0x02e0,0x045e/0x028e sh -c 'sleep 5; exec "$@"' sh %command%
   ```

   - `SDL_DYNAMIC_API` – use SDL 2.32 from the Steam Linux Runtime instead of the old static one.
   - `SDL_JOYSTICK_BLACKLIST_DEVICES` – comma-separated `0xVID/0xPID` list of your **physical**
     pads (and of other devices that show up as a joystick), so that only Steam's virtual pads
     are left. The example hides 8BitDo SN30 Pro/Pro+ in X-input mode over Bluetooth
     (`045e:02e0`) and Xbox 360 pads/clones (`045e:028e`). Find yours with
     `grep -B1 -A3 -E 'js[0-9]' /proc/bus/input/devices` (lines `I:` → `Vendor`, `Product`).
     Don't put `28de:11ff` (Steam's virtual pad) there. The Steam Controller itself needs no
     entry, Steam already hides it.
   - `sh -c 'sleep 5; exec "$@"' sh` – start the game 5 s later, after Steam has created all
     virtual pads. Not needed if the game sees all pads without it.

4. Check what the game found: `OctodadLog.txt` in the game directory, the last
   `Found joystick N …` lines should list `Microsoft X-Box 360 pad 0` … `3` and nothing else.

Then set up the co-op menu (Gamepad-1 … Gamepad-4 per limb). **Don't remap controls in the
game** – there is only one mapping, shared by all players.

Tested with SPEEDLINK TORID (X-input receiver, `045e:028e`), 8BitDo SN30 Pro and SN30 Pro+
(Bluetooth, X-input) and a Steam Controller (BLE) at the same time, Steam Linux Runtime
soldier 2.0.20261021, Arch Linux, GNOME (Wayland), game started from Steam.

Once, while testing, Gamepad-3 could lift a leg but not move it; after another restart with the
same setup everything worked. If it happens, restart the game.

No game files are distributed in this repository and none are modified except
`OctodadConfig.xml` (by the script, with backup).

## Debugging tips

- Which pads the game found: `grep 'Found joystick' OctodadLog.txt | tail`
- Which SDL it loaded: `grep -o '/[^ ]*libSDL2[^ ]*' /proc/$(pgrep -f '/OctodadDadliestCatch$')/maps | sort -u`
- What it has open: `ls -l /proc/$(pgrep -f '/OctodadDadliestCatch$')/fd | grep -E 'input|hidraw'`
- Why a pad isn't seen with the old SDL: `cat /proc/bus/input/devices` – its `eventN` is above 31.

---

<a name="slovensky"></a>
## Slovensky

**Problém:** Octodad: Dadliest Catch (Steam, natívna linuxová verzia) vidí len jeden gamepad,
takže co-op (až 4 hráči, každý ovláda jednu končatinu) sa nedá nastaviť. Bluetooth pady
nefungujú vôbec. Keď hra pady vidí, niektoré len zdvihnú nohu a nepohnú ňou, alebo ňou hýbu
len v jednej osi a naopak.

**Príčina:**
- Hra má SDL2 staticky zabudované v binárke, bez udev. To vidí len `/dev/input/event0` až
  `event31` a nemá hotplug. Na bežnom desktope sú tieto čísla obsadené a novšie pady
  (`event256+`) hra nevidí. Zabudované SDL má ale *dynamic API*, takže sa dá cez
  `SDL_DYNAMIC_API` presmerovať na SDL 2.32 zo Steam Linux Runtime bez úpravy súborov hry.
- Hra na Linuxe číta surové osi joysticku v poradí ako na Xbox 360. Pady s iným poradím osí
  (napr. 8BitDo cez HIDAPI) sa správajú zle. Steam Input z každého padu urobí virtuálny
  Xbox 360 pad s rovnakým poradím. Fyzické pady treba pred hrou skryť, inak ich vidí dvakrát.
- Steam vytvorí posledný virtuálny pad až chvíľu po štarte hry a hra nemá hotplug. Pomôže
  pozdržať štart hry.
- S SDL 2.32 je vo fullscreene čierna obrazovka, v okne hra funguje.

**Riešenie:** `./fix.sh` prepne hru do okna (`Graphics_FullscreenMode=0` v
`OctodadConfig.xml`, súbor je v UTF-32, so zálohou). V Steame zapni pre hru Steam Input a do
Launch Options daj:

```
SDL_DYNAMIC_API=/usr/lib/i386-linux-gnu/libSDL2-2.0.so.0 SDL_JOYSTICK_BLACKLIST_DEVICES=0x045e/0x02e0,0x045e/0x028e sh -c 'sleep 5; exec "$@"' sh %command%
```

Do `SDL_JOYSTICK_BLACKLIST_DEVICES` daj VID/PID svojich fyzických padov (a zariadení, ktoré
sa tvária ako joystick). Virtuálny pad Steamu (`28de:11ff`) tam nedávaj. V `OctodadLog.txt` by
mali byť len `Microsoft X-Box 360 pad 0` až `3`. Ovládanie v hre nepremapúvaj, mapovanie je
spoločné pre všetkých hráčov. Návrat: `./fix.sh --restore` a zmazať Launch Options.
