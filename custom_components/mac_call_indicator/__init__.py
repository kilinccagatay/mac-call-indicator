"""Boolean-only local push integration with independent availability."""
import asyncio
from aiohttp import web
from homeassistant.components import webhook
from homeassistant.core import callback
from homeassistant.const import EVENT_HOMEASSISTANT_STARTED
from homeassistant.helpers.event import async_call_later
from homeassistant.util import dt as dt_util

from .const import DOMAIN, LEASE_SECONDS, PLATFORMS
from .policy import command_for, validate_output
from .agenda import AgendaRuntime


async def async_setup(hass, config):
    from .api import PairView
    hass.http.register_view(PairView())
    return True


async def async_setup_entry(hass, entry):
    if not entry.data.get("agenda_webhook_id"):
        hass.config_entries.async_update_entry(entry, data={**entry.data, "agenda_webhook_id": webhook.async_generate_id()})
    runtime = MeetingRuntime(hass, entry)
    hass.data.setdefault(DOMAIN, {})[entry.entry_id] = runtime
    webhook.async_register(hass, DOMAIN, entry.title, entry.data["webhook_id"],
                           runtime.receive, local_only=True, allowed_methods=["POST"])
    webhook.async_register(hass, DOMAIN, entry.title + " agenda", entry.data["agenda_webhook_id"],
                           runtime.agenda.receive, local_only=True, allowed_methods=["POST"])
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    entry.async_on_unload(entry.add_update_listener(async_reload_entry))
    await runtime.apply_output()
    if not hass.is_running:
        entry.async_on_unload(hass.bus.async_listen_once(EVENT_HOMEASSISTANT_STARTED, runtime.reconcile))
    return True


async def async_reload_entry(hass, entry):
    await hass.config_entries.async_reload(entry.entry_id)


async def async_unload_entry(hass, entry):
    if not await hass.config_entries.async_unload_platforms(entry, PLATFORMS):
        return False
    runtime = hass.data[DOMAIN].pop(entry.entry_id)
    webhook.async_unregister(hass, entry.data["webhook_id"])
    webhook.async_unregister(hass, entry.data["agenda_webhook_id"])
    await runtime.close()
    return True


class MeetingRuntime:
    def __init__(self, hass, entry):
        self.hass, self.entry = hass, entry
        self.in_call = None
        self.last_report = None
        self.last_seen = None
        self.listeners = set()
        self.cancel_expiry = None
        self.lock = asyncio.Lock()
        self.closed = False
        self._config = {**entry.data, **entry.options}
        self.output_ok = True
        self.agenda = AgendaRuntime(hass, self.notify)

    @property
    def config(self):
        return self._config

    @callback
    def notify(self):
        for listener in tuple(self.listeners):
            listener()

    async def receive(self, hass, webhook_id, request):
        if request.content_length is not None and request.content_length > 128:
            return web.json_response({"error": "invalid_report"}, status=400)
        try:
            body = await request.json()
        except (ValueError, UnicodeError):
            return web.json_response({"error": "invalid_report"}, status=400)
        if not isinstance(body, dict) or set(body) != {"in_call"} or type(body["in_call"]) is not bool:
            return web.json_response({"error": "boolean_required"}, status=400)
        async with self.lock:
            if self.closed:
                return web.json_response({"error": "receiver_stopped"}, status=503)
            changed = self.in_call is None or self.in_call != body["in_call"]
            self.in_call = body["in_call"]
            self.last_report = dt_util.utcnow()
            self.last_seen = self.hass.loop.time()
            if self.cancel_expiry:
                self.cancel_expiry()
            self.cancel_expiry = async_call_later(self.hass, LEASE_SECONDS, self.expire)
            self.notify()
            if changed or not self.output_ok:
                await self.apply_output()
        return web.json_response({"accepted": True})

    async def expire(self, now):
        async with self.lock:
            # A cancelled timer can already be queued when a fresh report arrives.
            if self.last_seen is not None and self.hass.loop.time() - self.last_seen < LEASE_SECONDS:
                return
            self.in_call = None
            self.cancel_expiry = None
            self.notify()
            await self.apply_output()

    async def apply_output(self):
        try:
            # Offline turn-off must not require color capabilities to have
            # arrived yet during HA startup. Pairing already validates them.
            validate_output(self.config, self.hass.states if self.in_call is not None else None)
            command = command_for(self.config, self.in_call)
            if command:
                async with asyncio.timeout(4):
                    await self.hass.services.async_call(command.domain, command.action, command.data, blocking=True)
            self.output_ok = True
        except Exception:
            # Do not expose entities, webhook URLs, or credentials in logs.
            # Entity availability is independent of actuator success.
            self.output_ok = False
        self.notify()

    async def reconcile(self, event):
        async with self.lock:
            if not self.closed:
                await self.apply_output()

    async def close(self):
        await self.agenda.close()
        async with self.lock:
            self.closed = True
            if self.cancel_expiry:
                self.cancel_expiry()
            self.in_call = None
            await self.apply_output()
