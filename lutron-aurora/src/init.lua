local zcl_clusters = require "st.zigbee.zcl.clusters"
local Level = zcl_clusters.Level
local Basic = zcl_clusters.Basic
local TLC = zcl_clusters.TouchlinkCommissioning
local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local utils = require 'st.utils'

local PowerConfiguration = zcl_clusters.PowerConfiguration
local Groups = zcl_clusters.Groups

local CURRENT_LEVEL = "CURRENT_LEVEL"
local LAST_LEVEL_EVENT = "LAST_LEVEL_EVENT"
local DEVICE_GROUP = "DEVICE_GROUP"
--server: Basic, PowerConfiguration, Identify, TouchlinkCommissioning, 0xFC00 
--client: Identify, Groups, OnOff, Level, OTAUpgrade, TouchlinkCommissioning

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))
end

local function added_handler(self, device)
  for _, component in pairs(device.profile.components) do
    device:emit_component_event(component, capabilities.button.numberOfButtons({ value = 1 }))
    device:emit_event(capabilities.button.supportedButtonValues({"pushed"}, {visibility = { displayed = false }}))
  end
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
  device:emit_event(capabilities.switchLevel.level(0, { state_change = false }))
end

local battery_perc_attr_handler = function(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(utils.clamp_value(value.value, 0, 100)))
end

local function level_event_handler(driver, device, cmd)
  -- The device is essentially a stateless dimmer, it will always send events with a transition_time
  -- of 7 for on/off events and the value will be either 255 or 0, the memory on the device
  -- seems to reset after about 1 second so 0 is a bit rare. if the transition_time is 2 then
  -- the event is a dimmer event, the value with either be 2 for a reduction or > 3 for an increase.
  -- We are converting these dimmer events into individual steps based on the device preference
  local level_step = device.preferences.stepSize or 5
  local value = cmd.body.zcl_body.level.value
  local time = cmd.body.zcl_body.transition_time.value
  if time == 7 then
    device:emit_event(capabilities.button.button.pushed())
  elseif time == 2 then
    local current = device:get_field(CURRENT_LEVEL) or 0
    -- look up the last event which will either be 3 or some larger value
    local last_event = device:get_field(LAST_LEVEL_EVENT) or 3
    -- if the event is > than the last (or 3) then increase the switchLevel by
    -- level_step, otherwise reduce it by level_step
    if value > last_event then
      current = math.min(100, current + level_step)
    else
      current = math.max(0, current - level_step)
    end
    -- to guard against quick increase to decrease transitions we wait for 1 second and
    -- reset the last event level to 3
    driver:call_with_delay(1, function()
      device:set_field(LAST_LEVEL_EVENT, 3)
    end)
    device:emit_event(capabilities.switchLevel.level(math.floor(current)))
    device:set_field(CURRENT_LEVEL, current)
    device:set_field(LAST_LEVEL_EVENT, value)
  end
end

local function group_handler(driver, device, info)
  -- shortly after onboarding the device will send a GroupAdd event so we tell
  -- the hub to join that group. I am saving this in the device data because I feel
  -- like we should be leaving the group on device remove but that API doesn't seem to exist
  device:set_field(DEVICE_GROUP, info.body.zcl_body.group_id.value)
  driver:add_hub_to_zigbee_group(info.body.zcl_body.group_id.value)
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
    },
    cluster = {
      [Level.ID] = {
        [Level.server.commands.MoveToLevelWithOnOff.ID] = level_event_handler,
      },
      [Groups.ID] = {
        [Groups.server.commands.AddGroup.ID] = group_handler,
      }
    }
  },
}

local driver = ZigbeeDriver("Lutron Aurora", driver_template)
driver:run()
