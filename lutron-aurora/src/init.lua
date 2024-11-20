local zcl_clusters = require "st.zigbee.zcl.clusters"
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local utils = require "st.utils"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local read_responder = require "read_responder"

local PowerConfiguration = zcl_clusters.PowerConfiguration
local Groups = zcl_clusters.Groups

local LAST_LEVEL_EVENT = "LAST_LEVEL_EVENT"
local DEVICE_GROUP = "DEVICE_GROUP"
--server: Basic, PowerConfiguration, Identify, TouchlinkCommissioning, 0xFC00 
--client: Identify, Groups, OnOff, Level, OTAUpgrade, TouchlinkCommissioning

local function do_configure(driver, device)
  if not driver.environment_info.hub_zigbee_eui then
    return driver:call_with_delay(1, function()
      do_configure(driver, device)
    end)
  end
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, driver.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, driver.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30,
    21600, 1))
end

--- The shared logic for both `init` and `added` events.
local function start_device(driver, device)
  if not driver.environment_info.hub_zigbee_eui then
    return driver:call_with_delay(1, function()
      start_device(driver, device)
    end)
  end
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function added_handler(driver, device)
  start_device(driver, device)
  device:emit_event(capabilities.switch.switch.on({ state_change = false }))
  device:emit_event(capabilities.switchLevel.level(0, { state_change = false }))
end

local function init_handler(driver, device)
  start_device(driver, device)
  do_configure(driver, device)
end

local function battery_perc_attr_handler(_, device, value, _)
  device:emit_event(capabilities.battery.battery(utils.clamp_value(math.floor(value.value / 2), 0,
    100)))
end

local function handle_on_off(device, on)
  print("handle_on_off", device.label, level)
  if on then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function handle_level(device, level)
  print("handle_level", device.label, level)
  level = utils.clamp_value(level, 0, 100)
  level = math.floor(level)
  device:emit_event(capabilities.switchLevel.level(level))
end

local function level_event_handler(driver, device, cmd)
  -- The device will always send events with a transition_time
  -- of 7 for on/off events and the value will be either 255 or 0, the memory on the device
  -- seems to reset after about 1 second so 0 is a bit rare. If the transition_time is 2 then
  -- the event is a dimmer event, the value with either will be 2 for a reduction or > 3
  -- for an increase. We are converting these dimmer events into individual steps based on the
  -- device preference
  local level_step = device.preferences.stepSize or 5
  local value = cmd.body.zcl_body.level.value
  local time = cmd.body.zcl_body.transition_time.value
  print(device.label, "level_event_handler", value, time)
  if time == 7 then
    local current = device:get_latest_state("main", "switch", "switch", "off")
    print(device.label, "switch event", current)
    if current == "off" then
      handle_on_off(device, true)
    else
      handle_on_off(device, false)
    end
  elseif time == 2 then
    local current = device:get_latest_state("main", "switchLevel", "level", 0)
    print(device.label, "dimmer event", current)
    -- look up the last event which will either be 3 or some larger value
    local last_event = device:get_field(LAST_LEVEL_EVENT) or 3
    -- if the event is > than the last (or 3) then increase the switchLevel by
    -- level_step, otherwise reduce it by level_step
    local added = value > last_event and level_step or -level_step
    handle_level(device, current + added, 0, 100)
    device:set_field(LAST_LEVEL_EVENT, value)
    -- to guard against quick increase to decrease transitions we wait for 1 second and
    -- reset the last event level to 3
    driver:call_with_delay(1, function()
      device:set_field(LAST_LEVEL_EVENT, 3)
    end)
  end
  print("level_event_handler exit", device:get_latest_state("main", "switchLevel", "level", 0))
end

local function group_handler(driver, device, info)
  print("group_handler", device.label, info.body.zcl_body.group_id.value)
  -- shortly after onboarding the device will send a GroupAdd event so we tell
  -- the hub to join that group. I am saving this in the device data because I feel
  -- like we should be leaving the group on device remove but that API doesn't seem to exist
  device:set_field(DEVICE_GROUP, info.body.zcl_body.group_id.value, {persist = true})
  driver:add_hub_to_zigbee_group(info.body.zcl_body.group_id.value)
end

local driver_template = {
  supported_capabilities = {
    capabilities.battery,
    capabilities.switchLevel,
    capabilities.switch,
    capabilities.refresh,
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = added_handler,
    init = init_handler,
  },
  driver_lifecycle = function()
    os.exit(0)
  end,
  zigbee_handlers = {
    global = {
      [Level.ID] = {
        [zcl_commands.ReportAttribute.ID] = function(_driver, device, info)
          return read_responder(device)
        end
      },
    },
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
      },
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = function(_, _, info)
          print(utils.stringify_table(info, "CurrentLevel", true))
        end
      }
    },
    cluster = {
      [Level.ID] = {
        [Level.server.commands.MoveToLevelWithOnOff.ID] = level_event_handler,
      },
      [Groups.ID] = {
        [Groups.server.commands.AddGroup.ID] = group_handler,
      },
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = function(...)
          print("OnOff->On", ...)
        end,
        [OnOff.server.commands.Off.ID] = function(...)
          print("OnOff->OFF", ...)
        end,
      }
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = function(_, device)
        handle_on_off(device, true)
      end,
      [capabilities.switch.commands.off.NAME] = function(_, device)
        handle_on_off(device, false)
      end
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = function (_, device, cmd)
        print("level:", utils.stringify_table(cmd))
        handle_level(device, cmd.args.level)
      end,
    },
  },
}

local driver = ZigbeeDriver("Lutron Aurora", driver_template)
driver:run()
