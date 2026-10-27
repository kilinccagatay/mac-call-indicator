#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/build-app.sh
APP_DIR="$HOME/Applications"
SUPPORT_DIR="$HOME/Library/Application Support/MacCallIndicator"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT="$AGENT_DIR/local.MacCallIndicator.plist"
mkdir -p "$APP_DIR" "$SUPPORT_DIR" "$AGENT_DIR"
chmod 700 "$SUPPORT_DIR"
launchctl bootout "gui/$(id -u)/local.MacCallIndicator" 2>/dev/null || true
# Preserve settings outside the app; copying does not overwrite the webhook file.
ditto dist/MacCallIndicator.app "$APP_DIR/MacCallIndicator.app"
/usr/libexec/PlistBuddy -c Clear -c 'Add :Label string local.MacCallIndicator' \
    -c 'Add :ProgramArguments array' \
    -c "Add :ProgramArguments:0 string $APP_DIR/MacCallIndicator.app/Contents/MacOS/MacCallIndicator" \
    -c 'Add :RunAtLoad bool true' -c 'Add :KeepAlive bool true' \
    -c 'Add :ThrottleInterval integer 10' \
    -c "Add :StandardOutPath string $SUPPORT_DIR/status.log" \
    -c "Add :StandardErrorPath string $SUPPORT_DIR/errors.log" "$AGENT"
chmod 600 "$AGENT"
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo 'Installed. Approve Accessibility in System Settings if requested.'
