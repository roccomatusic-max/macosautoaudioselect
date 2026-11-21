#!/bin/bash
#
# Builds and installs DockAudio on this Mac, then walks you through setup.
#   bash install.sh
#
# Uses only tools that ship with macOS — no Xcode, no Homebrew.

set -u

SRC="$(cd "$(dirname "$0")" && pwd)/src"
APP="$HOME/Applications/DockAudio.app"
BUNDLE_ID="com.dockaudio.app"
AGENT_LABEL="com.dockaudio.launcher"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

fail() {
	echo "Install failed: $*" >&2
	exit 1
}

[ "$(uname -s)" = Darwin ] || fail "this only runs on a Mac."
[ -f "$SRC/DockAudio.applescript" ] || fail "run this from the downloaded folder (src/ is missing)."
[ -f "$SRC/dockaudio" ] || fail "run this from the downloaded folder (src/ is missing)."
[ -x /usr/bin/osacompile ] || fail "osacompile is missing from this Mac."

echo "Installing DockAudio…"

# stop and remove a previous copy
/usr/bin/pkill -f "DockAudio.app/Contents/MacOS/" >/dev/null 2>&1
/bin/launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1
rm -f "$HOME/Library/Application Support/DockAudio/heartbeat"
rm -rf "$APP"
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"

# build the background app (-s = stays open after launch)
/usr/bin/osacompile -s -o "$APP" "$SRC/DockAudio.applescript" || fail "could not build the app."
cp -X "$SRC/dockaudio" "$APP/Contents/Resources/dockaudio" || fail "could not copy the helper."
chmod 755 "$APP/Contents/Resources/dockaudio"

PLIST="$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST" || fail "could not edit Info.plist."
/usr/bin/plutil -replace CFBundleName -string "DockAudio" "$PLIST"
/usr/bin/plutil -replace LSUIElement -bool true "$PLIST" # no Dock icon
/usr/bin/plutil -replace NSAppleEventsUsageDescription -string \
	"DockAudio opens the Sound menu and selects your speaker when you plug into your dock." "$PLIST"

# keep the app from rewriting itself, then sign it so macOS can remember its permissions
chmod a-w "$APP/Contents/Resources/Scripts/main.scpt" 2>/dev/null
/usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null
/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || fail "could not sign the app."

# a rebuilt app counts as a new app to macOS; clear stale permission entries
# so the permission switch you see in System Settings is the one that works
/usr/bin/tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1
/usr/bin/tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1

# start at login
cat >"$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$AGENT_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-g</string>
		<string>$APP</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
EOF
/bin/launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST" >/dev/null 2>&1 || /usr/bin/open -g "$APP"

# put the `dockaudio` command somewhere convenient
CLI="$APP/Contents/Resources/dockaudio"
LINK=""
if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
	LINK=/usr/local/bin/dockaudio
else
	mkdir -p "$HOME/.local/bin"
	LINK="$HOME/.local/bin/dockaudio"
fi
ln -sf "$CLI" "$LINK"

echo "Installed: $APP"
echo

/bin/bash "$CLI" setup
STATUS=$?

echo
case ":$PATH:" in
*":$(dirname "$LINK"):"*) echo "From now on you can type:  dockaudio status" ;;
*)
	echo "The command lives at:  $LINK"
	echo "To be able to type just 'dockaudio', run this once and open a new Terminal window:"
	echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
	;;
esac
exit $STATUS
