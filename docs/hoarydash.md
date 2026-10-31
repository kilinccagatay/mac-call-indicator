# Optional HoaryDash / older tablet example

The tablet displays a Home Assistant meeting entity; it need not run the Mac
helper or control a light. Choose **Dashboard / status only**. Your original
source can remain **binary_sensor.mac_call_active**; the new integration creates
its own entity ID.

![Meeting badge on an actual panel](images/hoarydash-call-badge.png)

The badge is a red dot above **Toplantı**, visible only while the source is on.
There is no green/idle badge. Off, unknown, unavailable, a lost WebSocket and
an expired report hide it.

On a HoaryDash screen named **Ana**, add to the existing sensors.cards list:

~~~yaml
- entity_id: binary_sensor.mac_call_active
  label: ""
  icon: circle
~~~

Append [examples/hoarydash-call-badge.html](../examples/hoarydash-call-badge.html)
to the existing theme.custom string. For the new integration replace every
occurrence of **binary_sensor.mac_call_active** with your actual source ID.
Its DOM selector uses hyphens instead of dots: update
**binary_sensor-mac_call_active-** too. Adjust Ana and offsets to your layout.

The ES5-compatible script checks report freshness and connection health every
second. Credentials never belong in the dashboard. Both devices need accurate clocks.

Clear the old browser's cache if changes appear on a desktop but not the tablet.
No tablet APK, firmware or root-helper update is needed.

The [older-hardware panel project](https://github.com/kilinccagatay/home-assistant-legacy-panels)
contains the full layout, entity mappings, tablet setup and enclosure.
