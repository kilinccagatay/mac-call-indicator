from homeassistant.components.binary_sensor import BinarySensorEntity
from homeassistant.helpers.device_registry import DeviceInfo
from .const import DOMAIN, entity_id


async def async_setup_entry(hass, entry, async_add_entities):
    async_add_entities([MeetingSensor(hass.data[DOMAIN][entry.entry_id])])


class MeetingSensor(BinarySensorEntity):
    _attr_should_poll = False
    _attr_has_entity_name = True
    _attr_name = "Meeting"
    _attr_icon = "mdi:account-voice"

    def __init__(self, runtime):
        self.runtime = runtime
        entry = runtime.entry
        self._attr_unique_id = entry.entry_id
        self.entity_id = entity_id(entry.entry_id)
        self._attr_device_info = DeviceInfo(identifiers={(DOMAIN, entry.entry_id)},
                                            name=entry.title, manufacturer="Mac Call Indicator",
                                            model="Local meeting indicator")

    @property
    def available(self):
        return self.runtime.in_call is not None

    @property
    def is_on(self):
        return self.runtime.in_call

    @property
    def extra_state_attributes(self):
        return {"last_report_epoch": self.runtime.last_report.timestamp() if self.runtime.last_report else 0,
                "output_ok": self.runtime.output_ok}

    async def async_added_to_hass(self):
        self.runtime.listeners.add(self.async_write_ha_state)
        self.async_on_remove(lambda: self.runtime.listeners.discard(self.async_write_ha_state))
