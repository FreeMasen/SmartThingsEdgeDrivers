local json = require 'dkjson'
local log = require 'log'

function randomuuid()
  return string.format("%08x-%04x-%04x-%04x-%06x%06x",
    math.random(0, 0xffffffff),
    math.random(0, 0xffff),
    math.random(0, 0x0fff) + 0x4000, -- version 4, random
    math.random(0, 0x3fff) + 0x0800, -- variant 1
    math.random(0, 0xffffff),
    math.random(0, 0xffffff))
end

local function add_device(driver)
  log.debug('adding new device')
  local deviceNetworkId = randomuuid()
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
  if #(devices or {}) == 0 then
    add_device(driver)
  else
    log.debug('already have devices', #devices)
  end
end

return {
  disco = disco,
  add_device = add_device,
  randomuuid = randomuuid,
}
