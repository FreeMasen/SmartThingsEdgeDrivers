local json = require 'dkjson'
local log = require 'log'
local utils = require 'st.utils'

local function add_device(driver)
  log.debug('adding new device')
  local deviceNetworkId = utils.generate_uuid_v4()
  assert(driver.device_api.create_device(json.encode({
      type = 'LAN',
      deviceNetworkId = deviceNetworkId,
      label = 'Dream Presence',
      profileReference = 'dream-presence.v1',
      vendorProvidedName = 'Dream Presence',
  })))
  return deviceNetworkId
end

---Discover a single device
---@param driver Driver
local function disco(driver)
  local devices = driver.device_api.get_device_list()
  log.debug('current devices:', utils.stringify_table(devices, 'devices', true))
  if #(devices or {}) == 0 then
    add_device(driver)
  else
    log.debug('already have devices', #devices)
  end
end

return {
  disco = disco,
  add_device = add_device,
}
