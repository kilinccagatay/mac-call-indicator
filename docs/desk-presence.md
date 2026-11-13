# Desk Presence

Mac Call Indicator stays on the work Mac for Teams, Calendar and work Mac
availability. Desk Presence is an independent macOS login agent on the personal
Mac. It sends only the current session's `computer_active` boolean, at changes
and every ten seconds. It uses no Calendar or Accessibility permission.

1. Append the two blocks from [the example](../examples/desk-presence.yaml) to
   the existing Home Assistant template list. Change the work Mac entity ID in
   both places if your installation uses a different ID. Append the [work Mac
   timestamp section](../examples/desk-presence-work-timestamp.yaml) beside the
   existing work Mac receiver’s binary sensor section. It preserves the time
   after Home Assistant hides expired source attributes.
2. Set an independent random `desk_presence_webhook` secret. Check the Home
   Assistant configuration and reload templates. Keep the endpoint LAN-only.
3. Save `{"webhook":"https://YOUR_HA/api/webhook/YOUR_PRIVATE_ID"}` as
   `~/Library/Application Support/Desk Presence/config.json` with mode 600,
   then run `scripts/install-desk-presence.sh` as the logged-in macOS user.
4. Verify the two source entities separately. After verification, back up the
   Samsung helper's configuration and switch its state URL to
   `binary_sensor.desk_presence_active`, with computer state enabled and a
   120-second stale threshold. Restart the worker under its existing supervisor.

An unlocked session with its display awake counts as active. The aggregate
uses a report's original timestamp and allows either Mac to keep the desk
active. Explicit inactive reports are usable while fresh. A missing report
gets 120 seconds before it is treated as inactive. On startup, an absent work
Mac has the same grace period. An absent personal agent leaves the aggregate
uncertain until it has reported at least once. Locking counts as inactive
even when macOS continues running background jobs. Keep macOS automatic system
sleep disabled if those jobs need to continue while locked.

To roll back, restore the previous Samsung state URL and restart its worker.
Unload the personal agent with `launchctl bootout gui/$(id -u)/local.DeskPresence`
and remove its LaunchAgents plist to prevent the next login from reloading it.
Remove the two desk template blocks, the work Mac timestamp section and the
separate webhook secret if retiring the receiver.

On-device check, 2026-11-14. With the work Mac unavailable beyond the grace
period, locking the personal Mac yielded `OFFLINE`, followed by Android
`Asleep` and `Display Power: OFF`. Personal reports continued with the
session locked. Unlocking it yielded `ONLINE`, a helper wake request, and
`Awake / Display Power: ON`. Existing Samsung APK and supervisor were used.
The reverse physical case (work Mac active, personal Mac locked) and full
device regression remain pending. Swift tests and synthetic two-source
freshness cases passed.
