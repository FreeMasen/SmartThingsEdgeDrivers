local zcl_clusters = require "st.zigbee.zcl.clusters"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local data_types = require "st.zigbee.data_types"
local Level = zcl_clusters.Level
local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local utils = require 'st.utils'

local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local Groups = clusters.Groups

local ENTRIES_READ = "ENTRIES_READ"
local CURRENT_LEVEL = "CURRENT_LEVEL"
local LAST_LEVEL = "LAST_LEVEL"

local do_configure = function(self, device)
  print("do_configure")

  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))
  device:send(Level.attributes.CurrentLevel:configure_reporting(device, 5, 15, 1))
  self:add_hub_to_zigbee_group(0xf105)
  device:send(Groups.commands.AddGroup(device, 0xf105))

end

local function added_handler(self, device)
  print("added_handler")
  local number_of_buttons = 1
  for _, component in pairs(device.profile.components) do
    device:emit_component_event(component, capabilities.button.numberOfButtons({value = number_of_buttons}))
  end
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:send(Level.commands.MoveToLevelWithOnOff(device, 126, 2))
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
  device:emit_event(capabilities.button.button.level(0, { state_change = false }))
end

local battery_perc_attr_handler = function(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(utils.clamp_value(value.value, 0, 100)))
end

local function level_event_handler(driver, device, cmd)
  local value = cmd.body.zcl_body.level.value
  local time = cmd.body.zcl_body.transition_time.value
  print("level_event_handler", value, time)
  if time == 7 then
    device:emit_event(capabilities.button.button.pushed())
  elseif time == 2 then
    local current = device:get_field(CURRENT_LEVEL)
    
    local percent = ((value - 2) / (255 - 2)) * 100
    device:emit_event(capabilities.switchLevel.level(math.floor(percent)))
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
  cluster_configurations = {
    [capabilities.switchLevel.ID] = {
      {
        cluster = zcl_clusters.Level.ID,
        attribute = zcl_clusters.Level.attributes.CurrentLevel.ID,
        minimum_interval = 1,
        maximum_interval = 15,
        data_type = data_types.Uint8,
        reportable_change = 1
      }
    }
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




-- local function added_handler(self, device)
--   print("added_handler")
--   for _, component in pairs(device.profile.components) do
--     device:emit_component_event(component, capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }}))
--     device:emit_component_event(component, capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }}))
--   end
--   device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
--   device:emit_event(capabilities.button.button.pushed({state_change = false}))
-- end

-- local function do_configure(self, device)
--   print("do_configure")
--   device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
--   device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
--   device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
--   device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
--   device:send(device_management.build_bind_request(device, 0xfc00, self.environment_info.hub_zigbee_eui))
-- end

-- local dimming_remote = {
--   NAME = "Lutron Aurora",
--   supported_capabilities = {
--     capabilities.switch,
--     capabilities.switchLevel,
--   },
--   lifecycle_handlers = {
--     init = function(...) 
--       battery_defaults.build_linear_voltage_init(2.1, 3.0)(...)
--     end,
--     added = added_handler,
--     doConfigure = do_configure,
--     infoChanged = function(driver, device, ...)
--       print("infoChanged", utils.stringify_table({...}, nil, true))
--     end
  -- },
  -- zigbee_handlers = {
  --   cluster = {
  --     [Level.ID] = {
  --       [Level.server.commands.Move.ID] = function (driver, device, ...)
  --         print("cluster.Move", utils.stringify_table({ ... }, nil, true))
  --       end,
  --       [Level.server.commands.MoveWithOnOff.ID] = function (driver, device, ...)
  --         print("cluster.MoveWithOnOff", utils.stringify_table({ ... }, nil, true))
  --       end,
  --       [Level.server.commands.Stop.ID] = function (driver, device, ...)
  --         print("cluster.Stop", utils.stringify_table({ ... }, nil, true))
  --       end,
  --     },
  --     [OnOff.ID] = {
  --       [OnOff.server.commands.Off.ID] = function(driver, device, ...)
  --         print("cluster.Off", utils.stringify_table({ ... }, nil, true))
  --       end,
  --       [OnOff.server.commands.On.ID] = function(driver, device, ...)
  --         print("cluster.On", utils.stringify_table({...}, nil, true))
  --       end,
  --     }
  --   },
  --   attr = {
  --     [OnOff.ID] = {
  --       [OnOff.attributes.OnOff.ID] = function (driver, device, info)
  --         print("attr handler!", utils.stringify_table(info, "info", true))
  --       end
  --     }
  --   }
  -- },
  -- capabilities = {
  --   [capabilities.switch.ID] = {
  --     [capabilities.switch.commands.on.NAME] = function(...)
  --       print("Turn on")
  --       button_pushed_handler()
  --     end,
  --     [capabilities.switch.commands.off.NAME] = function(...)
  --       print("Turn Off")
  --       button_pushed_handler()
  --     end
  --   }
  -- },
--   device_tracker = {}
-- }
-- defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)

local driver = ZigbeeDriver("Lutron Aurora", driver_template)
driver:run()
