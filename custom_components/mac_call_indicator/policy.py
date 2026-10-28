"""Pure output policy: never interpret missing reports as available/free."""
from dataclasses import dataclass

MODES = ("status_only", "light_onoff", "light_color", "switch", "input_boolean")
DOMAINS = {"light_onoff": "light", "light_color": "light", "switch": "switch",
           "input_boolean": "input_boolean"}
COLOR_MODES = {"hs", "xy", "rgb", "rgbw", "rgbww"}


def validate_output(config, states=None):
    mode = config.get("output_mode", "status_only")
    if mode not in MODES:
        raise ValueError("invalid_mode")
    if mode == "status_only":
        return
    target = config.get("target_entity", "")
    if not isinstance(target, str) or target.count(".") != 1 or target.split(".")[0] != DOMAINS[mode]:
        raise ValueError("wrong_entity_type")
    if states is not None:
        entity = states.get(target)
        if entity is None:
            raise ValueError("entity_not_found")
        if mode == "light_color" and not COLOR_MODES.intersection(entity.attributes.get("supported_color_modes", [])):
            raise ValueError("color_not_supported")
    if config.get("offline_action", "off") not in ("off", "hold"):
        raise ValueError("invalid_offline_action")
    brightness = config.get("brightness_pct", 60)
    if type(brightness) is not int or not 1 <= brightness <= 100:
        raise ValueError("invalid_brightness")
    for key in ("busy_color", "idle_color"):
        color = config.get(key, [255, 0, 0] if key == "busy_color" else [0, 255, 0])
        if not isinstance(color, list) or len(color) != 3 or any(type(v) is not int or not 0 <= v <= 255 for v in color):
            raise ValueError("invalid_color")
    if type(config.get("idle_off", False)) is not bool:
        raise ValueError("invalid_idle_action")


@dataclass(frozen=True)
class Command:
    domain: str
    action: str
    data: dict


def command_for(config, in_call):
    """None means unavailable; it must never produce an idle/green command."""
    mode = config.get("output_mode", "status_only")
    if mode == "status_only":
        return None
    if in_call is None and config.get("offline_action", "off") == "hold":
        return None
    domain = DOMAINS[mode]
    on = in_call is True or (in_call is False and mode == "light_color" and not config.get("idle_off", False))
    data = {"entity_id": config["target_entity"]}
    if on and mode == "light_color":
        data["rgb_color"] = config.get("busy_color", [255, 0, 0]) if in_call else config.get("idle_color", [0, 255, 0])
        data["brightness_pct"] = config.get("brightness_pct", 60)
    return Command(domain, "turn_on" if on else "turn_off", data)
