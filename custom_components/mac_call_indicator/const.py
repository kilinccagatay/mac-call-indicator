DOMAIN = "mac_call_indicator"
LEASE_SECONDS = 40
PLATFORMS = ["binary_sensor"]


def entity_id(entry_id):
    return f"binary_sensor.mac_call_{entry_id.lower()}"
