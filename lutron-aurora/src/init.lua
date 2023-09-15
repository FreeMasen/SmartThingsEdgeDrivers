local zcl_clusters = require "st.zigbee.zcl.clusters"
local Level = zcl_clusters.Level
local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local utils = require 'st.utils'

local PowerConfiguration = zcl_clusters.PowerConfiguration
local Groups = zcl_clusters.Groups

local CURRENT_LEVEL = "CURRENT_LEVEL"

local do_configure = function(self, device)
  print("do_configure")

  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))
  -- device:send(Level.attributes.CurrentLevel:configure_reporting(device, 5, 15, 1))
  self:add_hub_to_zigbee_group(0xf105)
  -- device:send(Groups.commands.AddGroup(device, 0xf105))

end

local function added_handler(self, device)
  print("added_handler")
  local number_of_buttons = 1
  for _, component in pairs(device.profile.components) do
    device:emit_component_event(component, capabilities.button.numberOfButtons({ value = number_of_buttons }))
    device:emit_event(capabilities.button.supportedButtonValues({"pushed"}, {visibility = { displayed = false }}))
  end
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:send(Level.attributes.CurrentLevel:read(device))
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
  device:emit_event(capabilities.switchLevel.level(0, { state_change = false }))
end

local battery_perc_attr_handler = function(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(utils.clamp_value(value.value, 0, 100)))
end

local level_step = 10

local function level_event_handler(driver, device, cmd)
  local value = cmd.body.zcl_body.level.value
  local time = cmd.body.zcl_body.transition_time.value
  print("level_event_handler", value, time)
  if time == 7 then
    device:emit_event(capabilities.button.button.pushed())
  elseif time == 2 then
    local current = device:get_field(CURRENT_LEVEL) or 0
    if value > 3 then
      current = math.min(100, current + level_step)
    else
      current = math.max(0, current - level_step)
    end
    device:emit_event(capabilities.switchLevel.level(math.floor(current)))
    device:set_field(CURRENT_LEVEL, current)
  end
end

local function get_event_handler(name)
  return function(driver, device, cmd)
    print(name, utils.stringify_table(cmd, "cmd", true))
  end
end

local driver_template = {
  supported_capabilities = {
    capabilities.battery,
    capabilities.button,
    capabilities.switchLevel,
    capabilities.switch,
    capabilities.refresh,
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = added_handler,
    init = added_handler,
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
            },
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = function(driver, device, info)
          print("Level.attributes.CurrentLevel.ID", utils.stringify_table(info))
        end
      }
    },
    cluster = {
      [Level.ID] = {
        [Level.server.commands.MoveToLevelWithOnOff.ID] = level_event_handler,
      },
    }
  },
}

local driver = ZigbeeDriver("Lutron Aurora", driver_template)
driver:run()
