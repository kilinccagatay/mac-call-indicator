import voluptuous as vol
from homeassistant import config_entries
from homeassistant.components import webhook
from homeassistant.core import callback
from homeassistant.helpers import selector
from .const import DOMAIN
from .policy import MODES, validate_output


def output_schema(defaults=None):
    defaults = defaults or {}
    return {
        vol.Required("output_mode", default=defaults.get("output_mode", "status_only")):
            selector.SelectSelector(selector.SelectSelectorConfig(options=[
                {"value": mode, "label": label} for mode, label in zip(MODES, [
                    "Dashboard / status only", "Light — on/off", "Light — color",
                    "Switch", "Input boolean"])
            ])),
        (vol.Optional("target_entity", default=defaults["target_entity"]) if defaults.get("target_entity")
         else vol.Optional("target_entity")):
            selector.EntitySelector(selector.EntitySelectorConfig(
                domain=["light", "switch", "input_boolean"])),
        vol.Required("idle_off", default=defaults.get("idle_off", False)): bool,
        vol.Required("offline_action", default=defaults.get("offline_action", "off")):
            vol.In(["off", "hold"]),
        vol.Required("brightness_pct", default=defaults.get("brightness_pct", 60)):
            vol.All(vol.Coerce(int), vol.Range(min=1, max=100)),
        vol.Required("busy_color", default=defaults.get("busy_color", [255, 0, 0])):
            selector.ColorRGBSelector(),
        vol.Required("idle_color", default=defaults.get("idle_color", [0, 255, 0])):
            selector.ColorRGBSelector(),
    }


class ConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    VERSION = 1

    async def async_step_user(self, user_input=None):
        errors = {}
        if user_input is not None:
            try:
                validate_output(user_input, self.hass.states)
            except ValueError as error:
                errors["base"] = str(error)
            else:
                client_id = user_input.get("client_id", "")
                if client_id:
                    await self.async_set_unique_id(client_id)
                    self._abort_if_unique_id_configured()
                return self.async_create_entry(
                    title=user_input["name"],
                    data={**user_input, "client_id": client_id, "webhook_id": webhook.async_generate_id(), "agenda_webhook_id": webhook.async_generate_id()})
        return self.async_show_form(step_id="user", errors=errors, data_schema=vol.Schema({
            vol.Required("name", default="Meeting indicator"): str,
            **output_schema(),
        }))

    @staticmethod
    @callback
    def async_get_options_flow(config_entry):
        return OptionsFlow()


class OptionsFlow(config_entries.OptionsFlow):
    async def async_step_init(self, user_input=None):
        errors = {}
        defaults = {**self.config_entry.data, **self.config_entry.options}
        if user_input is not None:
            try:
                validate_output(user_input, self.hass.states)
            except ValueError as error:
                errors["base"] = str(error)
            else:
                return self.async_create_entry(title="", data=user_input)
        return self.async_show_form(step_id="init", errors=errors,
                                    data_schema=vol.Schema(output_schema(defaults)))
