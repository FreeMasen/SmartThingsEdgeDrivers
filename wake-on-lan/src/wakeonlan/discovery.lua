local log = require "log"
local utils = require "st.utils"

local function add_device(driver)
  log.trace("add_device")

  local device_name = "Wake on LAN"
  local device_id = utils.generate_uuid_v4()
  local device_info = {
    type = "LAN",
    device_network_id = device_id,
    profile = "wake-on-lan.v1",
    label = device_name,
    vendor_provided_label = device_name,
  }

  local success, err = driver:try_create_device(device_info)
  if success then
    log.info("Created device " .. device_name)
    return device_name, device_id
  else
    log.error("Could not create device: " .. err)
    return nil, nil, err
  end
end

local function discovery_handler(driver, options, continue)
  log.trace("discovery_handler")

  if continue() then
    local device_list = driver.device_api.get_device_list()
    if #device_list > 0 then
      log.debug("stopping discovery with " .. #device_list .. " devices")
      return
    end

    log.debug("Adding " .. driver.NAME .. " device")
    local device_name, device_id, err = add_device(driver)
    if err then
      log.error(err)
      return
    end

    log.info("Added " .. device_name)
  end
end

return {
  add_device = add_device,
  discovery_handler = discovery_handler,
}
