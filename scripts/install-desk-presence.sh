#!/bin/sh
# Provision config.json privately before running this as the logged-in user.
set -eu
cd "$(dirname "$0")/.."
support="$HOME/Library/Application Support/Desk Presence"
agent="$HOME/Library/LaunchAgents/local.DeskPresence.plist"
domain="gui/$(id -u)"
label=local.DeskPresence
test -r "$support/config.json"
chmod 600 "$support/config.json"
swift build -c release --product DeskPresence
bin=$(swift build -c release --show-bin-path)
mkdir -p "$HOME/Library/LaunchAgents"
if launchctl print "$domain/$label" >/dev/null 2>&1; then
    launchctl bootout "$domain/$label"
fi
install -m 700 "$bin/DeskPresence" "$support/DeskPresence"
python3 - "$agent" "$support" <<'PY'
import os
import plistlib
import sys
from pathlib import Path

agent, support = map(Path, sys.argv[1:])
with agent.open("wb") as stream:
    plistlib.dump({
        "Label": "local.DeskPresence",
        "ProgramArguments": [str(support / "DeskPresence"), str(support / "config.json")],
        "RunAtLoad": True,
        "KeepAlive": {"SuccessfulExit": False},
        "ThrottleInterval": 20,
    }, stream)
os.chmod(agent, 0o600)
PY
launchctl bootstrap "$domain" "$agent"
