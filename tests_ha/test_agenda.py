import asyncio
import json
import pytest
from homeassistant.util import dt as dt_util
from custom_components.mac_call_indicator.agenda import validate_report, AgendaRuntime


def report(now):
    return {"available": True, "generated_at": now, "valid_until": now + 90,
            "day_start": now - 1000, "day_end": now - 1000 + 86400,
            "events": [{"title": "Synthetic example", "start": now + 10, "end": now + 100}]}


def test_agenda_schema_bounds_and_no_company_fields():
    now = 1800000000
    assert validate_report(report(now), now)["available"]
    for change in [{"valid_until": now + 91}, {"generated_at": now - 91}, {"available": 1},
                   {"events": [{"title": "x", "start": now, "end": now + 1, "attendees": []}]},
                   {"events": [{"title": "x" * 161, "start": now, "end": now + 1}]},
                   {"events": [{"title": "x", "start": float("nan"), "end": now + 1}]},
                   {"events": [{}] * 65}, {"available": False}, {"notes": "excluded"}]:
        with pytest.raises(ValueError):
            validate_report({**report(now), **change}, now)


class Request:
    def __init__(self, body):
        self.content = asyncio.StreamReader()
        self.content.feed_data(json.dumps(body).encode())
        self.content.feed_eof()


@pytest.mark.asyncio
async def test_separate_receiver_expiry_and_invalid_reports_cannot_extend_lease():
    from types import SimpleNamespace
    now = dt_util.utcnow().timestamp()
    changed = []
    runtime = AgendaRuntime(SimpleNamespace(loop=asyncio.get_running_loop()), lambda: changed.append(True))
    response = await runtime.receive(None, "", Request(report(now)))
    assert response.status == 200 and runtime.fresh
    original = runtime.report
    assert (await runtime.receive(None, "", Request({"in_call": True}))).status == 400
    assert runtime.report is original
    runtime.report["valid_until"] = now - 1
    await runtime.expire(None)
    assert not runtime.fresh and runtime.report is None
    await runtime.close()
    assert (await runtime.receive(None, "", Request(report(now)))).status == 503
