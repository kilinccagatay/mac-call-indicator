#!/bin/sh
set -eu
launchctl bootout "gui/$(id -u)/local.MacCallIndicator" 2>/dev/null || true
echo 'Login service stopped. Home Assistant will expire the indicator within 40 seconds.'
echo 'Remove only these exact items manually when ready:'
echo "$HOME/Library/LaunchAgents/local.MacCallIndicator.plist"
echo "$HOME/Applications/MacCallIndicator.app"
echo "$HOME/Library/Application Support/MacCallIndicator"
echo 'Also revoke the app permission in System Settings and remove its HA template block.'
