# Home Assistant guide

Mac Call Indicator supplies a meeting source. Home Assistant owns any lamp,
switch, helper or dashboard that consumes it. Dashboard-only needs no target,
colors or automation.

## Install the integration

Compatibility baseline: Home Assistant 2025.3.4. Use a supported current server;
the pinned test dependency is not a recommendation to downgrade.

1. Copy the repository's **custom_components/mac_call_indicator** folder into your
   Home Assistant configuration directory's **custom_components/** folder.
   Alternatively add this repository URL as a **custom Integration repository**
   in HACS. This is not a claim of inclusion in HACS's default catalog.
2. Restart Home Assistant.
3. Open **Settings → Devices & services → Add integration → Mac Call Indicator**.
   Enter a generic name and initially select **Dashboard / status only**.
   Adding the integration registers the pairing endpoint; installing files alone
   is insufficient.
4. On the Mac open **Settings… → Connection**, enter the instance root URL and
   select **Home Assistant integration — automatic entity**.
5. Sign in or import a token. Choose an output, then click **Save & pair**.

The integration creates a persistent device/config entry and a read-only
**binary_sensor.mac_call_&lt;entry_id&gt;**. Its friendly name is the device's
**Meeting** entity. The Mac displays the actual ID returned by the entity registry.
You can rename it in Home Assistant; pair again to refresh the Mac's displayed ID.
Repeated pairing from the same Mac updates its entry instead of creating
duplicates. The first unpaired entry is claimed automatically.

This is a real integration/entity lifecycle, not a temporary REST state.
Existing entities, dashboards and YAML receivers are not migrated automatically.

## Connection and default address

**Use default** fills **http://homeassistant.local:8123/** when clicked. It never
saves or starts authentication. Local mDNS discovery must work on your network;
otherwise enter the IP address or HTTPS hostname manually.

The app accepts HTTPS and private-network HTTP. It rejects URL credentials, query
strings, fragments, non-root base URLs, public plain-HTTP addresses and redirects.
Certificate validation remains enabled. HTTP is unencrypted; prefer HTTPS.
The integration webhook is **local-only**. This project does not open ports or
alter network policy.

### Sign in with Home Assistant

The system authentication browser handles login. The Mac app never asks for your
Home Assistant password in a native field. It uses a random state, PKCE S256,
a registered native callback and token exchange against the chosen instance.

Native sign-in requires the server's OAuth discovery document to advertise S256.
Older servers may silently ignore PKCE; the app refuses that downgrade. Use a
long-lived token import on those versions.

The client ID is the repository's [static OAuth client document](../oauth-client.html),
served directly through GitHub's raw content endpoint. It declares
**mac-call-indicator://auth** as the callback. Home Assistant must be able to fetch
it. GitHub receives no callback, password, token or meeting report. Forks should
use their own HTTPS client document without redirects and keep the callback
declaration in its first 10 KB.

Access/refresh tokens are stored in **macOS Keychain**, scoped to the selected
server. The app refreshes the access token for authenticated setup operations.
Authentication is not an entity-specific permission: account permissions matter.
Pairing requires a Home Assistant administrator. Ongoing reports use a random
webhook, not an administrator bearer token.

### Import credentials

Create a long-lived access token in Home Assistant → your profile → Security.
Paste it into the masked token field in integration mode, or import private JSON:

~~~json
{
  "version": 1,
  "server_url": "https://homeassistant.example.com/",
  "access_token": "REPLACE_WITH_YOUR_PRIVATE_TOKEN"
}
~~~

For an existing webhook:

~~~json
{
  "version": 1,
  "server_url": "http://homeassistant.local:8123/",
  "webhook_url": "http://homeassistant.local:8123/api/webhook/REPLACE_WITH_RANDOM_SECRET"
}
~~~

Include exactly one of **access_token** or **webhook_url**. Import fills the form;
review and save to apply it. Connection/entity tests using a typed token store
it in Keychain for that server. Import files are credentials: keep them private
and out of Git. There is no secret-bearing export button.

**Disconnect** stops reporting and deletes the local receiver credential. It
clears tokens for the connected server and attempts OAuth refresh-token revocation.
If that server is unreachable, remove the session in your Home Assistant profile.
Imported long-lived tokens must be revoked manually. The legacy App Support
webhook file is not deleted; the disconnected preference prevents it from
silently becoming active again.

## Select an output

Use the Mac's **Output** tab or the Home Assistant integration's **Configure** options.

| Type | Target | Behavior |
| --- | --- | --- |
| Dashboard / status only | None | Publish status; never control an actuator |
| Light — on/off | light | On during meeting, off when idle |
| Light — color | Color-capable light | Busy/idle colors, brightness, optional idle-off |
| Switch | switch | On during meeting, off when idle |
| Input boolean | input_boolean | Mirror status into an existing helper |

**Load entities** lists compatible targets; manual entry is also supported.
Both Mac and server check the domain. The server verifies the target exists and
supports color when needed. A brightness-only or color-temperature-only light
must use on/off mode. Status-only ignores old target selections.

**When reports stop** defaults to **Turn target off**. **Leave target unchanged**
is an explicit opt-in and can leave the last color on; that is not fresh status.
Neither policy generates an idle/green command from a missing report.

Home Assistant options are authoritative. Saving the Mac form replaces that
entry's output settings; do not save an old Mac form after editing Home Assistant
options unless you intend to replace them.

Use either built-in target control or a blueprint for a target. To control several
lamps, select status-only and create multiple blueprint automations. Previous lamp
settings are not snapshotted/restored; the selected policy determines the output.

## Existing webhook or YAML setup

The original private **~/Library/Application Support/MacCallIndicator/webhook-url**
file remains supported until a new connection is saved. Installing the Mac app
does not change its receiver or entity. Saving that URL in Settings activates
the Keychain copy, without deleting the original file.

Merge [examples/home-assistant.yaml](../examples/home-assistant.yaml) into the
existing template list, preserving other entries. Generate a private, unguessable
webhook ID and define **mac_call_indicator_webhook** in **secrets.yaml**. Validate
the configuration, then reload template entities or restart.

The source is normally **binary_sensor.mac_call_active**; check the actual ID if
that name already exists. The updated receiver becomes unavailable after 40 seconds
at the next five-second watchdog tick. Older receivers may simply turn off.
Before using green for idle, upgrade the receiver or use the supplied blueprints,
which independently require a fresh **last_report_epoch** timestamp.

The random webhook URL is the credential; no separate API token is required.
Unknown webhook IDs may also return HTTP 200, so **Test connection** in webhook
mode verifies reachability only. Confirm reception on the source entity.

## Automations and dashboards

Import these GitHub file URLs under Home Assistant → Automations & scenes →
Blueprints → Import:

- [On/off light, switch or input_boolean](../blueprints/automation/meeting_onoff.yaml)
- [Color meeting lamp](../blueprints/automation/meeting_color.yaml)

Select the source and a target using the domain-filtered picker, set options and
enable the automation. Color support is checked before commands are issued.
The blueprint watchdog checks stale reports every five seconds. No special lamp
integration is needed beyond its existing Home Assistant integration.

A dashboard can show only an active meeting:

~~~yaml
type: conditional
conditions:
  - entity: binary_sensor.REPLACE_WITH_YOUR_MEETING_ENTITY
    state: "on"
card:
  type: markdown
  content: "🔴 Meeting"
~~~

Off, unknown and unavailable hide this card. It has no green/idle indicator.
For legacy browsers see [the optional HoaryDash guide](hoarydash.md).

## Verify the complete path

1. A newly paired source is unavailable until a fresh report arrives.
2. With Accessibility approved, click **Test meeting for 10 seconds**. Confirm
   the source and chosen output. It returns to actual call/manual status without
   overwriting a manual deadline.
3. Start a manual meeting, then start/end a Teams call. The deadline must remain
   unchanged. Expiry leaves an ongoing real call active.
4. Quit the helper or disconnect its network. After 40 seconds the integration
   source must be unavailable and the target must follow the offline policy.
   Blueprint/YAML watchdogs may take up to five additional seconds.
5. Reconnect. Fresh true/false reports restore on/off availability.
6. Restart Home Assistant. Never show green before a fresh false report.

On Home Assistant **2026.10.0**, native sign-in, refresh, entity listing and pairing
were exercised with the actual Mac app. A Philips Hue Iris in XY mode physically
showed idle green, meeting red, green after the temporary test ended, and off after
the Mac reporter stopped. The source became unavailable. Its original scene and
the prior dashboard-only webhook connection were restored after validation.

The source's **last_report_epoch** attribute supports stale-state dashboards.
**output_ok** indicates the last built-in target operation. If false, check the
target exists, supports the mode and is reachable. Failures retry on a subsequent
heartbeat. This integration does not log sensitive targets or credentials.

## References

- [Authentication API](https://contributors.home-assistant.io/core/internals/auth-api/)
- [Webhook security](https://www.home-assistant.io/docs/automation/trigger/#webhook-security)
- [Binary sensor states](https://www.home-assistant.io/integrations/binary_sensor/)
- [Light capabilities](https://contributors.home-assistant.io/core/entities/light/)
