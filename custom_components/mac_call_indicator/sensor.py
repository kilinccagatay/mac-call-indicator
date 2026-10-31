"""Agenda metadata is exposed only on the explicit optional agenda entity."""
from homeassistant.components.sensor import SensorEntity
from .const import DOMAIN


async def async_setup_entry(hass, entry, async_add_entities):
    async_add_entities([AgendaSensor(hass.data[DOMAIN][entry.entry_id])])


class AgendaSensor(SensorEntity):
    _attr_should_poll = False
    _attr_has_entity_name = True
    _attr_name = "Agenda"
    _attr_icon = "mdi:calendar-clock"
    _unrecorded_attributes = frozenset({"events"})

    def __init__(self, runtime):
        self.runtime = runtime
        self._attr_unique_id = runtime.entry.entry_id + "_agenda"
        self.entity_id = "sensor.mac_call_agenda_" + runtime.entry.entry_id.lower()

    @property
    def available(self):
        return self.runtime.agenda.fresh

    @property
    def native_value(self):
        return "ready" if self.runtime.agenda.fresh else None

    @property
    def extra_state_attributes(self):
        report = self.runtime.agenda.report if self.runtime.agenda.fresh else None
        return {"events": report["events"] if report else [],
                "day_start": report["day_start"] if report else 0,
                "valid_until": report["valid_until"] if report else 0}

    async def async_added_to_hass(self):
        self.runtime.listeners.add(self.async_write_ha_state)
        self.async_on_remove(lambda: self.runtime.listeners.discard(self.async_write_ha_state))
