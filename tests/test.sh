#!/bin/bash
#
# Tests the decision logic in src/dockaudio (dock detection, plug/unplug/wake
# handling, retries) without a Mac, by standing in fake `ioreg` and
# `system_profiler` commands. The fixtures are hand-written in the format those
# tools print; they are not captures from a real machine.
#
#   bash tests/test.sh
#
# The clicking in the Sound menu (src/DockAudio.applescript) can only be
# exercised on a real Mac and is not covered here.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CLI="$HERE/../src/dockaudio"
FIX="$HERE/fixtures"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# macOS ships the "one true awk"; use it when available so the awk programs
# are checked against the same dialect.
mkdir -p "$WORK/bin"
if command -v original-awk >/dev/null 2>&1; then
	ln -s "$(command -v original-awk)" "$WORK/bin/awk"
fi
cat >"$WORK/bin/fake-ioreg" <<EOF
#!/bin/bash
cat "$WORK/ioreg.now" 2>/dev/null
EOF
cat >"$WORK/bin/fake-sysprof" <<EOF
#!/bin/bash
cat "$WORK/audio.now" 2>/dev/null
EOF
chmod +x "$WORK/bin/fake-ioreg" "$WORK/bin/fake-sysprof"

export PATH="$WORK/bin:$PATH"
export DOCKAUDIO_DIR="$WORK/data"
export DOCKAUDIO_LOG="$WORK/log"
export DOCKAUDIO_IOREG="$WORK/bin/fake-ioreg"
export DOCKAUDIO_SYSTEM_PROFILER="$WORK/bin/fake-sysprof"

TAB="$(printf '\t')"
PASS=0
FAIL=0

check() { # description expected actual
	if [ "$2" = "$3" ]; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
	fi
}

dock() { cp "$FIX/ioreg-docked.txt" "$WORK/ioreg.now"; }
undock() { cp "$FIX/ioreg-undocked.txt" "$WORK/ioreg.now"; }
audio() { cp "$FIX/audio-$1.json" "$WORK/audio.now"; }
tick() { bash "$CLI" tick; }
config() { printf '%s=%s\n' "$1" "$2" >>"$DOCKAUDIO_DIR/config"; }
state() { sed -n "s/^$1=//p" "$DOCKAUDIO_DIR/state"; }
age_heartbeat() { echo $(($(date +%s) - $1)) >"$DOCKAUDIO_DIR/heartbeat"; }

SONOS="Rocco's Room / Office"
DOCK_IDS="2109:0545: 0bda:8156:4013000001_A7 05ac:024f:F0T1234ABCD"

fresh() { # start every scenario from a configured, just-launched app
	rm -rf "$DOCKAUDIO_DIR" "$DOCKAUDIO_LOG"
	mkdir -p "$DOCKAUDIO_DIR"
	config SPEAKER_NAME "$SONOS"
	config SPEAKER_IDENT "sound-device-42"
	config UNDOCK_OUTPUT "MacBook Pro Speakers"
	config UNDOCK_IDENT ""
	config DOCK_IDS "$DOCK_IDS"
	config DOCK_MIN_MATCH 2
	config DOCK_SETTLE_SECONDS 0
	config RETRY_GAP_SECONDS 0
	bash "$CLI" app-started
}

SWITCH_SONOS="switch${TAB}auto${TAB}$SONOS${TAB}sound-device-42"
SWITCH_BUILTIN="switch${TAB}auto${TAB}MacBook Pro Speakers${TAB}"

# --- parsing ---------------------------------------------------------------
fresh
dock
check "usb list when docked" \
	"046d:c52b:${TAB}USB Receiver
05ac:024f:F0T1234ABCD${TAB}Magic Keyboard
0bda:8156:4013000001_A7${TAB}USB 10/100/1G/2.5G LAN
2109:0545:${TAB}CalDigit TS4 Hub" "$(bash "$CLI" usb)"
check "docked" 1 "$(bash "$CLI" docked)"
undock
check "usb list when undocked" "046d:c52b:${TAB}USB Receiver" "$(bash "$CLI" usb)"
check "undocked" 0 "$(bash "$CLI" docked)"

audio builtin
check "output: built-in" "MacBook Pro Speakers${TAB}coreaudio_device_type_builtin" "$(bash "$CLI" current-output)"
audio sonos
check "output: airplay, name unescaped" "$SONOS${TAB}airplay" "$(bash "$CLI" current-output)"
: >"$WORK/audio.now"
check "output: unknown" "" "$(bash "$CLI" current-output)"

# --- not configured --------------------------------------------------------
rm -rf "$DOCKAUDIO_DIR"
dock
audio builtin
check "no config: nothing happens" "none" "$(tick)"

# --- plug in ---------------------------------------------------------------
fresh
undock
audio builtin
check "undocked at start: nothing" "none" "$(tick)"
dock
check "first sighting of dock is not trusted yet" "none" "$(tick)"
check "second sighting: switch to speaker" "$SWITCH_SONOS" "$(tick)"
bash "$CLI" result auto "ok${TAB}selected in the Sound menu"
check "after success nothing is owed" "" "$(state want_name)"
check "steady state while docked" "none" "$(tick)"

# --- unplug ----------------------------------------------------------------
audio sonos
undock
check "first missing check is not trusted yet" "none" "$(tick)"
check "second missing check: back to built-in" "$SWITCH_BUILTIN" "$(tick)"
audio builtin
check "confirmed by the actual output device" "none" "$(tick)"
check "nothing owed after unplug" "" "$(state want_name)"

# --- a one-tick blip is ignored ---------------------------------------------
fresh
dock
audio sonos
tick >/dev/null # startup while docked, already on the speaker
undock
check "blip: one missing check" "none" "$(tick)"
dock
check "blip: dock is back, nothing happens" "none" "$(tick)"
undock
check "blip: counter restarted" "none" "$(tick)"

# --- unplug while on headphones --------------------------------------------
fresh
dock
audio headphones
tick >/dev/null
bash "$CLI" result auto "ok${TAB}x"
undock
tick >/dev/null
check "unplug on headphones: left alone" "none" "$(tick)"
check "unplug on headphones: nothing owed" "" "$(state want_name)"

# --- unplug with no fallback configured ------------------------------------
fresh
sed -i.bak 's/^UNDOCK_OUTPUT=.*/UNDOCK_OUTPUT=/' "$DOCKAUDIO_DIR/config"
dock
audio sonos
tick >/dev/null
undock
tick >/dev/null
check "unplug without fallback: nothing" "none" "$(tick)"

# --- docked at login --------------------------------------------------------
fresh
dock
audio builtin
check "docked at startup: switch immediately" "$SWITCH_SONOS" "$(tick)"

# --- already on the speaker -------------------------------------------------
fresh
dock
audio sonos
check "already on speaker: no menu flicker" "none" "$(tick)"

# --- retries and giving up --------------------------------------------------
fresh
dock
audio builtin
check "attempt 1" "$SWITCH_SONOS" "$(tick)"
bash "$CLI" result auto "fail${TAB}NOT_FOUND: not in the menu"
sed -i.bak 's/^want_next=.*/want_next=0/' "$DOCKAUDIO_DIR/state"
check "attempt 2 after a failure" "$SWITCH_SONOS" "$(tick)"
bash "$CLI" result auto "clicked${TAB}clicked, not confirmed"
sed -i.bak 's/^want_next=.*/want_next=0/' "$DOCKAUDIO_DIR/state"
audio sonos
check "unconfirmed click verified by output device" "none" "$(tick)"
check "nothing owed after verification" "" "$(state want_name)"

fresh
dock
audio builtin
n=0
while [ $n -lt 6 ]; do
	check "attempt $((n + 1)) of 6" "$SWITCH_SONOS" "$(tick)"
	n=$((n + 1))
done
check "gives up after 6 attempts" "none" "$(tick)"
check "nothing owed after giving up" "" "$(state want_name)"

# --- permission problems stop retrying --------------------------------------
fresh
dock
audio builtin
tick >/dev/null
bash "$CLI" result auto "fail${TAB}NO_ACCESSIBILITY"
check "permission failure: no retry loop" "none" "$(tick)"

# --- wake from sleep --------------------------------------------------------
fresh
dock
audio sonos
tick >/dev/null
audio builtin # AirPlay dropped while asleep
age_heartbeat 600
check "wake while docked: reconnect" "$SWITCH_SONOS" "$(tick)"

fresh
config REAPPLY_ON_WAKE 0
dock
audio sonos
tick >/dev/null
audio builtin
age_heartbeat 600
check "wake with reapply off: nothing" "none" "$(tick)"

# --- requests from the command line -----------------------------------------
fresh
undock
printf 'r1\tlist\t\t\n' >"$DOCKAUDIO_DIR/command"
check "list request is passed to the app" "list${TAB}r1${TAB}${TAB}" "$(tick)"
printf 'r2\tswitch\tKitchen\tsound-device-7\n' >"$DOCKAUDIO_DIR/command"
check "switch request" "switch${TAB}r2${TAB}Kitchen${TAB}sound-device-7" "$(tick)"
bash "$CLI" result r2 "ok${TAB}selected"
check "answer is filed for the caller" "ok${TAB}selected" "$(cat "$DOCKAUDIO_DIR/result.r2")"

# request/answer round trip with a stand-in for the app
fresh
(
	i=0
	while [ $i -lt 40 ]; do
		if [ -f "$DOCKAUDIO_DIR/command" ]; then
			line="$(tick)"
			id="$(printf '%s' "$line" | cut -f2)"
			bash "$CLI" result "$id" "ok${TAB}3
Living Room${TAB}sound-device-1${TAB}0
MacBook Pro Speakers${TAB}sound-device-2${TAB}1"
			exit 0
		fi
		sleep 0.25
		i=$((i + 1))
	done
) &
date +%s >"$DOCKAUDIO_DIR/heartbeat" # looks like a running app
check "dockaudio list end to end" \
	"  Looking at your Sound menu (it will open by itself for a few seconds)…
    1) Living Room
    2) MacBook Pro Speakers  (current)" "$(bash "$CLI" list)"
wait

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" = 0 ]
