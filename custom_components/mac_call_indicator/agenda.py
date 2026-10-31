"""Optional calendar channel, separate from call reports and actuator policy."""
import asyncio
import math
from aiohttp import web
from homeassistant.helpers.event import async_call_later
from homeassistant.util import dt as dt_util


def validate_report(body, now):
    keys = {"available", "generated_at", "valid_until", "day_start", "day_end", "events"}
    if not isinstance(body, dict) or set(body) != keys or type(body["available"]) is not bool:
        raise ValueError("invalid_report")
    for key in keys - {"available", "events"}:
        if type(body[key]) not in (int, float) or not math.isfinite(body[key]):
            raise ValueError("invalid_time")
    generated, until = body["generated_at"], body["valid_until"]
    if not now - 90 <= generated <= now + 5 or not generated < until <= generated + 90:
        raise ValueError("expired_or_invalid_lease")
    first, last = body["day_start"], body["day_end"]
    if not now - 90000 <= first <= now + 3 * 86400 or not 23 * 3600 <= last - first <= 25 * 3600:
        raise ValueError("invalid_day")
    events = body["events"]
    if not isinstance(events, list) or len(events) > 64 or (not body["available"] and events):
        raise ValueError("invalid_events")
    for event in events:
        if not isinstance(event, dict) or set(event) != {"title", "start", "end"}:
            raise ValueError("invalid_event")
        if not isinstance(event["title"], str) or len(event["title"]) > 160:
            raise ValueError("invalid_title")
        if any(type(event[k]) not in (int, float) or not math.isfinite(event[k]) for k in ("start", "end")):
            raise ValueError("invalid_event_time")
        if not event["start"] < event["end"] or not (event["start"] < last and event["end"] > first):
            raise ValueError("outside_selected_day")
    return body


class AgendaRuntime:
    def __init__(self, hass, notify):
        self.hass, self.notify = hass, notify
        self.report = None
        self.cancel = None
        self.closed = False
        self.lock = asyncio.Lock()

    @property
    def fresh(self):
        return bool(self.report and self.report["available"] and dt_util.utcnow().timestamp() < self.report["valid_until"])

    async def receive(self, hass, webhook_id, request):
        # Streaming bound also covers chunked requests without Content-Length.
        try:
            try:
                async with asyncio.timeout(5):
                    raw = await request.content.readexactly(65537)
            except asyncio.IncompleteReadError as error:
                raw = error.partial
            if len(raw) > 65536:
                raise ValueError("too_large")
            import json
            body = validate_report(json.loads(raw), dt_util.utcnow().timestamp())
        except (ValueError, TypeError, UnicodeError, TimeoutError):
            return web.json_response({"error": "invalid_agenda"}, status=400)
        async with self.lock:
            if self.closed:
                return web.json_response({"error": "receiver_stopped"}, status=503)
            self.report = body
            if self.cancel:
                self.cancel()
            delay = max(0, body["valid_until"] - dt_util.utcnow().timestamp())
            self.cancel = async_call_later(self.hass, delay, self.expire)
            self.notify()
        return web.json_response({"accepted": True})

    async def expire(self, now):
        async with self.lock:
            if self.report and dt_util.utcnow().timestamp() >= self.report["valid_until"]:
                self.report = None
                self.cancel = None
                self.notify()

    async def close(self):
        async with self.lock:
            self.closed = True
            if self.cancel:
                self.cancel()
            self.report = None
