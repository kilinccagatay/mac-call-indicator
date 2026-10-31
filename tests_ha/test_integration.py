"""Run against real Home Assistant, without connecting to a user's instance."""
import asyncio
import importlib
import shutil
from datetime import timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pytest
import pytest_asyncio
from aiohttp.test_utils import TestClient, TestServer
from homeassistant.auth import auth_manager_from_config
from homeassistant.auth.const import GROUP_ID_ADMIN, GROUP_ID_USER
from homeassistant.config_entries import ConfigEntries
from homeassistant.core import HomeAssistant
from homeassistant import loader
from homeassistant.setup import async_setup_component
from homeassistant.helpers import entity_registry, device_registry, area_registry
from homeassistant.util import dt as dt_util

from custom_components.mac_call_indicator.const import DOMAIN
from custom_components.mac_call_indicator.policy import command_for, validate_output


@pytest_asyncio.fixture
async def hass(tmp_path):
    source = Path(__file__).resolve().parents[1] / "custom_components"
    shutil.copytree(source, tmp_path / "custom_components", ignore=shutil.ignore_patterns("__pycache__"))
    instance = HomeAssistant(str(tmp_path))
    loader.async_setup(instance)
    instance.config.skip_pip = True
    instance.config.time_zone = "UTC"
    await asyncio.gather(entity_registry.async_load(instance), device_registry.async_load(instance),
                         area_registry.async_load(instance))
    instance.auth = await auth_manager_from_config(instance, [], [])
    instance.config_entries = ConfigEntries(instance, {})
    await instance.config_entries.async_initialize()
    assert await async_setup_component(instance, "http", {"http": {"server_host": "127.0.0.1", "server_port": 18823}})
    assert await async_setup_component(instance, DOMAIN, {})
    yield instance
    await instance.async_stop(force=True)


async def create_entry(hass, **output):
    result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": "user"}, data={
        "name": "Test meeting indicator", "client_id": "6247f5b8-1516-40c8-8f5a-242026aef188",
        "output_mode": "status_only", **output,
    })
    assert result["type"] == "create_entry", result
    await hass.async_block_till_done()
    entry = result["result"]
    return entry, hass.data[DOMAIN][entry.entry_id]


class Report:
    def __init__(self, body):
        self.body = body
        self.content_length = 24
    async def json(self):
        return self.body


@pytest.mark.asyncio
async def test_real_entity_availability_fresh_reports_expiry_and_unload(hass):
    entry, runtime = await create_entry(hass)
    sensor = next(s for s in hass.states.async_all("binary_sensor") if s.attributes.get("friendly_name", "").endswith("Meeting"))
    assert sensor.state == "unavailable"
    response = await runtime.receive(hass, "", Report({"in_call": True}))
    assert response.status == 200
    await hass.async_block_till_done()
    assert hass.states.get(sensor.entity_id).state == "on"
    old = runtime.last_report
    await runtime.receive(hass, "", Report({"in_call": True}))
    assert runtime.last_report >= old
    # A queued stale expiry cannot override a fresh heartbeat.
    await runtime.expire(dt_util.utcnow())
    assert runtime.in_call is True
    runtime.last_seen -= 41
    await runtime.expire(dt_util.utcnow())
    await hass.async_block_till_done()
    assert hass.states.get(sensor.entity_id).state == "unavailable"
    await runtime.receive(hass, "", Report({"in_call": False}))
    await hass.async_block_till_done()
    assert hass.states.get(sensor.entity_id).state == "off"
    assert await hass.config_entries.async_unload(entry.entry_id)


@pytest.mark.asyncio
async def test_color_commands_only_on_transition_and_never_green_when_offline(hass):
    hass.states.async_set("light.test_meeting", "off", {"supported_color_modes": ["rgb"]})
    commands = []
    async def record(call):
        commands.append((call.service, dict(call.data)))
    hass.services.async_register("light", "turn_on", record)
    hass.services.async_register("light", "turn_off", record)
    entry, runtime = await create_entry(hass, output_mode="light_color", target_entity="light.test_meeting")
    assert commands[-1] == ("turn_off", {"entity_id": "light.test_meeting"})
    commands.clear()
    await runtime.receive(hass, "", Report({"in_call": True}))
    await runtime.receive(hass, "", Report({"in_call": True}))
    assert len(commands) == 1
    assert commands[-1][1]["rgb_color"] == [255, 0, 0]
    await runtime.receive(hass, "", Report({"in_call": False}))
    assert commands[-1][1]["rgb_color"] == [0, 255, 0]
    runtime.last_seen -= 41
    await runtime.expire(dt_util.utcnow())
    assert commands[-1] == ("turn_off", {"entity_id": "light.test_meeting"})


@pytest.mark.asyncio
async def test_dashboard_and_invalid_payloads_never_control_actuators(hass):
    entry, runtime = await create_entry(hass, target_entity="light.never_touch")
    for payload in [{"in_call": "true"}, {"in_call": 1}, {"in_call": True, "meeting_name": "must_reject"}, []]:
        assert (await runtime.receive(hass, "", Report(payload))).status == 400
    assert runtime.in_call is None
    assert (await runtime.receive(hass, "", Report({"in_call": True}))).status == 200
    assert command_for(runtime.config, True) is None


@pytest.mark.parametrize("mode,entity", [
    ("light_onoff", "light.desk"), ("switch", "switch.desk"), ("input_boolean", "input_boolean.meeting")
])
def test_output_type_routing(mode, entity):
    config = {"output_mode": mode, "target_entity": entity}
    validate_output(config)
    assert command_for(config, True).action == "turn_on"
    assert command_for(config, False).action == "turn_off"
    assert command_for(config, None).action == "turn_off"
    assert command_for({**config, "offline_action": "hold"}, None) is None
    with pytest.raises(ValueError):
        validate_output({**config, "target_entity": "binary_sensor.read_only"})


@pytest.mark.asyncio
async def test_pairing_admin_gate_idempotency_and_type_validation(hass):
    from custom_components.mac_call_indicator.api import PairView
    from homeassistant.components.http.const import KEY_HASS_USER
    await create_entry(hass)
    class Request(dict):
        app = {"hass": hass}
        content_length = 200
        async def json(self):
            return {"client_id": "6247f5b8-1516-40c8-8f5a-242026aef188",
                    "name": "Test meeting indicator", "output_mode": "status_only"}
    view = PairView()
    assert (await view.post(Request({KEY_HASS_USER: SimpleNamespace(is_admin=False)}))).status == 403
    request = Request({KEY_HASS_USER: SimpleNamespace(is_admin=True)})
    first = await view.post(request)
    second = await view.post(request)
    assert first.status == second.status == 200
    assert first.text == second.text
    assert len(hass.config_entries.async_entries(DOMAIN)) == 1


@pytest.mark.asyncio
async def test_http_auth_pairing_and_webhook_round_trip(hass):
    await create_entry(hass)
    user = await hass.auth.async_create_user("Local integration test", group_ids=[GROUP_ID_ADMIN])
    refresh = await hass.auth.async_create_refresh_token(user, client_id="https://example.com/")
    token = hass.auth.async_create_access_token(refresh)
    async with TestClient(TestServer(hass.http.app)) as client:
        config = {"client_id": "6247f5b8-1516-40c8-8f5a-242026aef188",
                  "name": "Local test", "output_mode": "status_only"}
        assert (await client.post("/api/mac_call_indicator/pair", json=config)).status == 401
        response = await client.post("/api/mac_call_indicator/pair", json=config,
                                     headers={"Authorization": f"Bearer {token}"})
        assert response.status == 200
        pairing = await response.json()
        await hass.async_block_till_done()
        assert (await client.get(pairing["webhook_path"])).status == 405
        response = await client.post(pairing["webhook_path"], json={"in_call": True})
        assert await response.json() == {"accepted": True}
        await hass.async_block_till_done()
        assert hass.states.get(pairing["entity_id"]).state == "on"
        assert (await client.post(pairing["webhook_path"], json={"in_call": "true"})).status == 400
        response = await client.post(pairing["webhook_path"], json={"in_call": False})
        assert response.status == 200
        await hass.async_block_till_done()
        assert hass.states.get(pairing["entity_id"]).state == "off"


@pytest.mark.asyncio
@pytest.mark.parametrize("filename,target", [
    ("meeting_onoff.yaml", "switch.meeting"), ("meeting_color.yaml", "light.meeting")
])
async def test_blueprints_validate_and_stale_false_never_means_free(hass, filename, target):
    from homeassistant.components.blueprint.models import Blueprint, BlueprintInputs
    from homeassistant.components.blueprint.schemas import BLUEPRINT_SCHEMA
    from homeassistant.components.automation.config import async_validate_config_item
    from homeassistant.helpers.template import Template
    from homeassistant.util import yaml as yaml_util
    path = Path(__file__).resolve().parents[1] / "blueprints" / "automation" / filename
    blueprint = Blueprint(yaml_util.load_yaml(str(path)), schema=BLUEPRINT_SCHEMA, expected_domain="automation")
    inputs = BlueprintInputs(blueprint, {"use_blueprint": {"input": {
        "meeting_entity": "binary_sensor.test_meeting", "target_entity": target
    }}})
    inputs.validate()
    expanded = inputs.async_substitute()
    assert await async_validate_config_item(hass, "automation", expanded)
    fresh = Template(expanded["variables"]["fresh"], hass)
    hass.states.async_set("binary_sensor.test_meeting", "off", {"last_report_epoch": dt_util.utcnow().timestamp()})
    assert fresh.async_render({"source": "binary_sensor.test_meeting"}) is True
    hass.states.async_set("binary_sensor.test_meeting", "off", {"last_report_epoch": dt_util.utcnow().timestamp() - 41})
    assert fresh.async_render({"source": "binary_sensor.test_meeting"}) is False
    hass.states.async_set("binary_sensor.test_meeting", "unavailable", {"last_report_epoch": dt_util.utcnow().timestamp()})
    assert fresh.async_render({"source": "binary_sensor.test_meeting"}) is False


@pytest.mark.asyncio
async def test_legacy_template_rejects_invalid_idle_and_expires(hass):
    import yaml
    from homeassistant.helpers.template import Template
    from homeassistant.core import State
    class Loader(yaml.SafeLoader):
        pass
    Loader.add_constructor("!secret", lambda loader, node: loader.construct_scalar(node))
    path = Path(__file__).resolve().parents[1] / "examples" / "home-assistant.yaml"
    entity = yaml.load(path.read_text(), Loader=Loader)["template"][0]["binary_sensor"][0]
    old = State("binary_sensor.test_meeting", "on", {"last_report_epoch": dt_util.utcnow().timestamp() - 41})
    variables = {"this": old, "trigger": {"id": "watchdog"}}
    assert Template(entity["availability"], hass).async_render(variables) is False
    variables["trigger"] = {"id": "report", "json": {"in_call": "false"}}
    assert Template(entity["state"], hass).async_render(variables) is True
    assert Template(entity["availability"], hass).async_render(variables) is False
    variables["trigger"] = {"id": "report", "json": {"in_call": False}}
    assert Template(entity["state"], hass).async_render(variables) is False
    assert Template(entity["availability"], hass).async_render(variables) is True
    variables["trigger"] = {"id": "startup"}
    assert Template(entity["availability"], hass).async_render(variables) is False


@pytest.mark.asyncio
async def test_agenda_entity_is_separate_from_call_state(hass):
    import json
    entry, runtime = await create_entry(hass)
    now = dt_util.utcnow().timestamp()
    body = {"available": True, "generated_at": now, "valid_until": now + 90,
            "day_start": now - 1000, "day_end": now - 1000 + 86400,
            "events": [{"title": "Synthetic example", "start": now, "end": now + 100}]}
    content = asyncio.StreamReader()
    content.feed_data(json.dumps(body).encode()); content.feed_eof()
    assert (await runtime.agenda.receive(hass, "", SimpleNamespace(content=content))).status == 200
    await hass.async_block_till_done()
    agenda_id = "sensor.mac_call_agenda_" + entry.entry_id.lower()
    agenda = hass.states.get(agenda_id)
    assert agenda.state == "ready" and len(agenda.attributes["events"]) == 1
    assert runtime.in_call is None, "Agenda must not write the actual call report or actuate outputs"
    await runtime.receive(hass, "", Report({"in_call": True}))
    runtime.agenda.report["valid_until"] = now - 1
    await runtime.agenda.expire(None)
    await hass.async_block_till_done()
    assert hass.states.get(agenda_id).state == "unavailable"
    assert hass.states.get(agenda_id).attributes.get("events", []) == []
    assert runtime.in_call is True, "Agenda expiry cannot cancel a real call"
