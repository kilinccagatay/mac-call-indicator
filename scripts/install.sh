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
MIGRATE_LOGIN=false
if [ -f "$AGENT" ]; then MIGRATE_LOGIN=true; fi
launchctl bootout "gui/$(id -u)/local.MacCallIndicator" 2>/dev/null || true
pkill -x MacCallIndicator 2>/dev/null || true
# Preserve settings outside the app; copying does not overwrite the webhook file.
ditto dist/MacCallIndicator.app "$APP_DIR/MacCallIndicator.app"
if [ "$MIGRATE_LOGIN" = true ]; then
    mv "$AGENT" "$SUPPORT_DIR/legacy-launch-agent.plist"
    "$APP_DIR/MacCallIndicator.app/Contents/MacOS/MacCallIndicator" --enable-login
fi
open "$APP_DIR/MacCallIndicator.app"
echo 'Installed. Toggle login startup from the menu bar. New installations default to off.'
