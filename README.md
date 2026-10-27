# Mac Call Indicator

Experimental, local-only call status for Home Assistant and old HoaryDash panels.
It sends exactly one boolean, `in_call`, without meeting titles, numbers,
participants, calendar access, Microsoft Graph, Entra registration, or Teams tokens.

## Current status

The Teams desktop test call exposed Leave, microphone controls, and a timer via
macOS Accessibility. Those controls disappeared after the test ended. The
installed background helper detected the test call, and the HoaryDash badge
appeared, stayed visible while muted, and disappeared after call end. This
version targets Teams only; Phone/FaceTime support is out of scope. Tested with
Teams desktop 26183.1901.4874.5228; ordinary work meetings and other UI languages
still need separate validation.

Receiver validation used six synthetic boolean heartbeats ten seconds apart.
The badge remained visible beyond the initial 40-second window. After reports
stopped, the browser hid the badge and the Home Assistant entity was confirmed
off at 48 seconds after the last report. Navigating to another dashboard tab
also removed the badge from view. Five unit tests cover the detection rules.
The badge was also verified on a Denver TAC-70051 running the Crosswalk-based
WallPanel Legacy browser. Its old HTTP cache initially retained the previous
dashboard; restarting the app alone did not refresh it. Refresh the page with
cache clearing if a newly added badge appears in a desktop browser but not on
the panel. The physical panel showed the test badge and hid it when normal
false reports resumed, without installing an APK or changing firmware.

The helper uses public Accessibility APIs, not private CallKit APIs or Teams logs.
It scans only Teams windows, skips editable fields, never reads window titles,
and retains only control evidence. A positive state requires an end control,
a microphone control, and an elapsed timer greater than zero in the same window.
Busy status and microphone activity alone cannot trigger it. This is a UI-based
heuristic and can break when Teams changes its labels or window structure.

## Build and local validation

Use a Mac with Xcode command-line tools and Swift 5.9 or later:

```sh
swift test
sh scripts/build-app.sh
dist/MacCallIndicator.app/Contents/MacOS/MacCallIndicator --once
```

Grant Accessibility access only through normal macOS Privacy & Security settings,
if your organization's policy allows it. The optional `--request-access` command
opens the standard permission flow. No TCC database changes, bypasses, admin
policy changes, or disabling SIP are part of this project.

Test a connected call, muted call, background window, ringing, pre-join, call end,
app quit, lock, permission loss, and network loss before enabling a login service.
Unknown/unreadable states report false. This avoids a stuck-on indicator but may
hide it when a window is inaccessible. Do not claim universal call detection.

## Start at login

Install with `sh scripts/install.sh`, then use the menu bar's
**Start at Login** checkbox. This uses macOS
`SMAppService.mainApp`. Unchecking it leaves the current app running but prevents
startup at the next login. Quit exits the current app without a watchdog
relaunch; it does not change the login preference. New installations default to
off. The installer migrates an older project LaunchAgent to the standard login
item and preserves its enabled startup behavior. macOS may require approval in
Login Items; the menu shows a mixed checkmark while approval is pending.

The installed executable also supports `--login-status`, `--enable-login`, and
`--disable-login` for installation/removal. These do not need Accessibility.

## Required permissions

The app does not request microphone, camera, screen recording, input monitoring,
Contacts, Calendar, or Apple Events permissions. It performs read-only AX queries
against Teams. macOS describes Accessibility access broadly; it cannot grant a
permission restricted to just the call toolbar. Startup never prompts for access;
request it explicitly with `--request-access` if needed. The only network request
is the configured Home Assistant boolean webhook.

Development builds are ad-hoc signed. Rebuilding can invalidate the previous
Accessibility approval even when the name and path stay the same. If a restarted
login service still reports permission required, remove its old entry and add the
current installed app again through System Settings. Do not reset the whole
permission database. The background process's `observer_authorized` status is the
relevant check; a command run from an already authorized terminal may differ.
The running menu-bar app writes only `in_call` and `observer_authorized` to the
private `~/Library/Application Support/MacCallIndicator/status.json` file every
ten seconds and on call changes. Check its modification time to ensure the app
is running; this file never contains call details or webhook credentials.

## Home Assistant

Merge `examples/home-assistant.yaml` into the existing template configuration.
Generate a long random webhook ID in the private `secrets.yaml` file. The webhook
is POST-only and local-only. Store its full URL in a mode-0600 file at:

```text
~/Library/Application Support/MacCallIndicator/webhook-url
```

Use HTTPS when available. Plain HTTP provides no transport encryption; restrict
such a setup to a trusted private LAN. Never expose the webhook to the internet.
The helper refuses redirects, sends no cookies, and emits no endpoint in logs.

The helper refreshes the state every ten seconds and on changes. The receiver
must turn the state off after 40 seconds without refresh and on startup.
Verify this timeout on the installed Home Assistant version, including repeated
true heartbeats and server restart, before relying on it.

Show `binary_sensor.mac_call_active` only on the HoaryDash Home screen. Treat
unknown/unavailable as hidden. Preserve existing layout and use an ordinary red
CSS dot if the old browser cannot render emoji. No tablet APK or firmware change
is necessary.

For a screen named `Ana`, add this card to its existing `sensors.cards` list:

```yaml
- entity_id: binary_sensor.mac_call_active
  label: ""
  icon: circle
```

Append `examples/hoarydash-call-badge.html` to the existing `theme.custom` string.
The subscribed card is hidden and a small noninteractive red badge appears in
the bottom-right corner of Ana. Other screens do not contain it. The generated
server heartbeat timestamp lets the browser expire stale true states too;
WebSocket disconnection hides the badge. Both machines need accurate clocks.
Adjust the screen ID and corner offsets to match your own layout.

## Privacy and publication

`.local/`, `dist/`, logs, and build artifacts are ignored. The actual webhook URL
belongs outside this repository. Do not add real endpoints, secrets, preference
dumps, screenshots of work calls, or company logs. Home Assistant will receive
only `{"in_call":true}` or `{"in_call":false}`.

Before a public release, document exactly which app versions and call scenarios
were tested and supply login-service installation and removal instructions.
No public repository or release is created by the build script.
