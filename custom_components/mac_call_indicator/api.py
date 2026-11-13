"""Admin-authenticated one-time pairing; ongoing reports use only a webhook."""
import uuid
from aiohttp import web
from homeassistant.components import webhook
from homeassistant.components.http import HomeAssistantView
from homeassistant.components.http.const import KEY_HASS_USER
from homeassistant.helpers import entity_registry as er
from .const import DOMAIN, entity_id
from .policy import validate_output

ALLOWED = {"client_id", "name", "output_mode", "target_entity", "brightness_pct",
           "busy_color", "idle_color", "idle_off", "offline_action"}


class PairView(HomeAssistantView):
    url = "/api/mac_call_indicator/pair"
    name = "api:mac_call_indicator:pair"
    requires_auth = True

    async def post(self, request):
        if not request[KEY_HASS_USER].is_admin:
            return web.json_response({"error": "admin_required_for_pairing"}, status=403)
        hass = request.app["hass"]
        if request.content_length is not None and request.content_length > 4096:
            return web.json_response({"error": "invalid_configuration"}, status=400)
        try:
            data = await request.json()
            if not isinstance(data, dict) or set(data) - ALLOWED:
                raise ValueError("invalid_configuration")
            if not isinstance(data["client_id"], str):
                raise ValueError("invalid_client_id")
            uuid.UUID(data["client_id"])
            if not isinstance(data["name"], str) or not 1 <= len(data["name"].strip()) <= 64:
                raise ValueError("invalid_name")
            validate_output(data, hass.states)
        except (ValueError, TypeError, KeyError):
            return web.json_response({"error": "invalid_configuration_or_entity"}, status=400)
        entries = hass.config_entries.async_entries(DOMAIN)
        entry = next((e for e in entries if e.data.get("client_id") == data["client_id"]), None)
        if entry is None:
            # Claim the entry created when the integration was first added.
            entry = next((e for e in entries if not e.data.get("client_id")), None)
        if entry:
            updated = {**data, "webhook_id": entry.data["webhook_id"], "agenda_webhook_id": entry.data.get("agenda_webhook_id") or webhook.async_generate_id()}
            hass.config_entries.async_update_entry(entry, title=data["name"], data=updated,
                                                   options={}, unique_id=data["client_id"])
        else:
            result = await hass.config_entries.flow.async_init(
                DOMAIN, context={"source": "user"}, data=data)
            if result["type"] != "create_entry":
                return web.json_response({"error": "pairing_failed"}, status=409)
            entry = result["result"]
        registry = er.async_get(hass)
        sensor = registry.async_get_entity_id("binary_sensor", DOMAIN, entry.entry_id) or entity_id(entry.entry_id)
        return web.json_response({
            "webhook_path": f"/api/webhook/{entry.data['webhook_id']}",
            "entity_id": sensor,
            "lease_seconds": 40,
            "agenda_webhook_path": f"/api/webhook/{entry.data['agenda_webhook_id']}",
            "agenda_entity_id": registry.async_get_entity_id("sensor", DOMAIN, entry.entry_id + "_agenda") or "sensor.mac_call_agenda_" + entry.entry_id.lower(),
        })
