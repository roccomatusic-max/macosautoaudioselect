# DockAudio

Plug your MacBook into its dock and the sound moves to your Sonos speakers by
itself. Unplug, and it goes back to the MacBook speakers.

## How it works

Sonos speakers are Wi-Fi speakers, so they are not a normal Mac sound device —
but most of them (2018 and later) support AirPlay, which makes them appear in
the Mac's Sound menu. macOS has no supported command to select an AirPlay
speaker, so DockAudio does what you would do by hand:

1. A small background app checks every 3 seconds whether the dock's USB
   devices are present.
2. When the dock appears, it opens the Sound menu, clicks your speaker, and
   closes the menu. You will see the menu flick open for a second or two.
3. When the dock disappears, it clicks your MacBook speakers the same way
   (only if the sound was still on the Sonos — headphones are left alone).

It also reconnects when the Mac wakes from sleep on the dock, since AirPlay
drops during sleep.

## Requirements

- A Mac on macOS 13 or later.
- A Sonos speaker that supports AirPlay 2 and shows up when you click the
  Sound icon in the menu bar. Check this first: if you can pick it there by
  hand, DockAudio can pick it for you. Older models without AirPlay
  (Play:1, Play:3, Playbar…) only appear if grouped with a newer one in the
  Sonos app.
- The Mac and the Sonos on the same network.

Nothing else to install: it is built from tools that ship with macOS.

## Install

1. Download this repository (green **Code** button → **Download ZIP**) and
   unzip it.
2. Open **Terminal**, type `bash ` (with the space), drag `install.sh` from
   the unzipped folder into the Terminal window, and press Return.
3. Follow the three setup steps it walks you through:
   - **Permissions** — macOS asks you to allow DockAudio under
     *Privacy & Security → Accessibility*. This is what lets it click the
     Sound menu.
   - **Speaker** — pick your Sonos from the list, and what to switch back to
     when you unplug.
   - **Dock** — plug or unplug the dock when asked, so it learns what your
     dock looks like.

That's it. It starts by itself every time you log in.

## Commands

```bash
dockaudio status        # what it currently sees
dockaudio test          # switch to the Sonos right now
dockaudio test undock   # switch back right now
dockaudio logs          # what it has been doing
dockaudio setup         # redo setup (new dock, new speaker…)
dockaudio stop          # pause it;  `dockaudio start` to resume
dockaudio uninstall     # remove everything
```

If typing `dockaudio` says "command not found", the installer printed the
full path to use at the end of its output.

## Settings

Settings live in `~/Library/Application Support/DockAudio/config`, one
`NAME=value` per line. Setup writes the main ones; these optional ones can be
added by hand:

| Setting | Default | Meaning |
| --- | --- | --- |
| `DOCK_VOLUME` | *(unset)* | Volume (0–100) to set after switching to the Sonos. |
| `REAPPLY_ON_WAKE` | `1` | Reconnect after waking from sleep on the dock. `0` to turn off. |
| `DOCK_MIN_MATCH` | half the dock's devices | How many of the dock's USB devices must be present to count as docked. |
| `MAX_ATTEMPTS` | `6` | How many times to try if the speaker is not in the menu yet. |

## Good to know

- **AirPlay has a delay of about two seconds.** Music is fine; video players
  compensate so picture and sound stay in sync; games and video calls will
  feel laggy. That is a property of AirPlay, not of this tool.
- **Peripherals plugged into the dock count as part of it.** If you rearrange
  what is plugged into the dock a lot and it stops recognising it, run
  `dockaudio setup` again.
- **After reinstalling, macOS asks for the Accessibility permission again.**
  A rebuilt app is a new app as far as macOS is concerned.

## Troubleshooting

`dockaudio logs` says what happened on the last plug or unplug, including why
a switch failed.

- *"… is not in the Sound menu right now"* — the Sonos was not reachable over
  AirPlay. Check that it is powered, and that you can select it by hand.
- *Nothing happens on docking* — run `dockaudio status`. If it says the dock
  is not connected while it is, run `dockaudio setup` again.
- *It stopped working after a macOS update* — Apple rearranges the Sound menu
  now and then. Run this and share the file so the menu-reading code can be
  adjusted:

  ```bash
  dockaudio dump > ~/Desktop/dockaudio-dump.txt
  ```

## For developers

- `src/dockaudio` — bash; all the decisions (dock detection, plug/unplug/wake
  events, retries) and the command-line interface.
- `src/DockAudio.applescript` — the background applet; asks `dockaudio tick`
  what to do every 3 seconds and performs the clicks in the Sound menu.
- `install.sh` — compiles the applet with `osacompile`, signs it ad hoc,
  installs a LaunchAgent that opens it at login.
- `tests/test.sh` — exercises the decision logic with stand-ins for `ioreg`
  and `system_profiler`. Runs on Linux or macOS: `bash tests/test.sh`. The
  Sound-menu clicking can only be exercised on a real Mac.
