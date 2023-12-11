local Driver = require 'st.driver'
local log = require 'log'
local utils = require 'st.utils'
local json = require 'dkjson'
local capabilities = require 'st.capabilities'
local socket = require 'cosock'
local metrics_report = require "metrics_report"
local server = require "server"


local function add_device(driver, profileReference, vendorProvidedName)
  local device_info = {
    type = 'LAN',
    deviceNetworkId = string.format('%s', os.time()),
    label = vendorProvidedName or 'prefs-size',
    profileReference = profileReference or 'no-prefs.v1',
    vendorProvidedName = vendorProvidedName or 'no-prefs',
  }
  local device_info_json = json.encode(device_info)
  assert(driver.device_api.create_device(device_info_json))
end

local function disco(driver, opts, cont)
  print('starting disco', utils.stringify_table(opts))
  local device_list = driver.device_api.get_device_list()
  if not next(device_list) and cont() then
    print('discovering a device')
    add_device(driver, "no-prefs.v1", "no-prefs")
  end
end

local function handle_cap(driver, device, dir)
  
  
  local ev
  if dir == "on" then
    ev = capabilities.switch.switch.on()
  else
    ev = capabilities.switch.switch.off()
  end
  device:emit_state(ev)
end

local driver = Driver("prefs-size", {
  discovery = disco,
  lifecycle_handlers = {
    init = emit_state,
    added = emit_state,
    deleted = function() log.debug("device deleted") end,
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = function(driver, device)
        device:emit_event(capabilities.switch.switch.on())
      end,
      [capabilities.switch.commands.off.NAME] = function(...)
        log.info('Turn Off')
        device:emit_event(capabilities.switch.switch.off())
      end
    }
  }
})
driver.add_device = add_device
server(driver)
driver:run()
