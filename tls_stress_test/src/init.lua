local cosock = require 'cosock'
local log = require "log"
local capabilities = require 'st.capabilities'
local Driver = require 'st.driver'
local json = require "dkjson"
local https = require "https"


local ON = capabilities.switch.switch.on()
local OFF = capabilities.switch.switch.off()

local function add_device(driver, device_id, device_number)
  local device_id = string.match(device_id, '[^%s]+')
  log.trace('add_device', device_id, device_number)
  if device_number == nil then
      log.debug('determining current device count')
      local device_list = driver.device_api.get_device_list()
      device_number = #device_list
  end
  local device_name = 'TLS ' .. device_number
  log.debug('adding device ' .. device_name)

  local device_info = {
      type = 'LAN',
      deviceNetworkId = device_id,
      label = device_name,
      profileReference = 'tls-stress-test.v1',
      vendorProvidedName = device_name,
  }
  local device_info_json = json.encode(device_info)
  local success, msg = driver.device_api.create_device(device_info_json)
  if success then
      log.debug('successfully created device')
      return device_name, device_id
  end
  log.error(string.format('unsuccessful create_device %s', msg))
  return nil, nil, msg
end

local function device_added(driver, device)
  device:emit_event(OFF)
end

function emit_event(driver, device, event)
  device:emit_event(event)
  if not (type(device.preferences.httpsUrl) == "string"
    and device.preferences.httpsUrl:match("^https://")) then
    return log.error(string.format("Invalid `httpsUrl` preference: %q", device.preferences.httpsUrl))
  end
  for i=1, (device.preferences.burstSize or 1) do
    print("spawning ", i )
    cosock.spawn(function()
      print(https.request(device.preferences.httpsUrl))
    end)
  end
end

local driver = Driver('Tls Stress Test', {
  lifecycle_handlers = {
      init = device_added,
      added = device_added,
  },
  capability_handlers = {
      [capabilities.switch.ID] = {
          [capabilities.switch.commands.on.NAME] = function(driver, device)
              emit_event(driver, device, ON)
            end,
            [capabilities.switch.commands.off.NAME] = function(driver, device)
              emit_event(driver, device, OFF)
          end
      },
  },
  discovery = function(driver, opts, cont)
    log.debug("disco")
    local dev_ct = #assert(driver.device_api.get_device_list())
    if cont() and dev_ct < 1 then
      add_device(driver, "single-device-id", 1)
    end
  end,
  driver_lifecycle = function(driver, event)
    os.exit()
  end
})

driver:run()
