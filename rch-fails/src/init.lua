local Driver = require 'st.driver'
local log = require 'log'
local utils = require 'st.utils'
local json = require 'dkjson'
local capabilities = require 'st.capabilities'
local cosock = require 'cosock'

local function emit_state(driver, device, event)
  local ev_ctor
  if event.command == "off" then
    ev_ctor = capabilities.switch.switch.off
  else
    ev_ctor = capabilities.switch.switch.on
  end
  device:emit_event(ev_ctor())
  if not driver.task_tx then
    return log.debug("emit before device")
  end
  driver.task_tx:send(event or {device_id = device.id, msg = "No event for device..."})
end

local function disco(driver, opts, cont)
  print('starting disco', utils.stringify_table(opts))
  local device_list = driver.device_api.get_device_list()
  if not next(device_list) and cont() then
    print('discovering a device')
    local device_info = {
        type = 'LAN',
        deviceNetworkId = string.format('%s', os.time()),
        label = 'rch-fails',
        profileReference = 'rch-fails.v1',
        vendorProvidedName = 'rch-fails',
    }
    local device_info_json = json.encode(device_info)
    assert(driver.device_api.create_device(device_info_json))
  end
end

local function device_added(driver, device)
  if driver.task_tx then
    return log.warn("duplicate drvice added event")
  end
  emit_state(driver, device, {command = "off"})
  local task_tx, task_rx = cosock.channel.new()
  local device_tx, device_rx = cosock.channel.new()
  task_rx:settimeout(60)
  driver:register_channel_handler(device_rx, function()
    log.debug("Device message")
    local msg, err = device_rx:receive()
    if msg then
      log.debug("message from device", msg)
    else
      log.error("Error from device_rx", err)
    end
  end)
  driver.task_tx = task_tx
  cosock.spawn(function()
    while true do
      local ev, err = task_rx:receive()
      if not ev then
        log.error("Error from task_rx", err)
      else
        log.debug(string.format("event from driver: %s", utils.stringify_table(ev)))
      end
      device_tx:send(string.format("Event from %s", os.time()))
    end
  end)
end


local driver = Driver('rch-fails', {
  discovery = disco,
  lifecycle_handlers = {
    init = device_added,
    added = device_added,
    deleted = function() log.debug("device deleted") end,
  },
  driver_lifecycle = function()
    os.exit()
  end,
  capability_handlers = {
    [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = function(...)
            emit_state(...)
        end,
        [capabilities.switch.commands.off.NAME] = function(...)
          emit_state(...)
        end
    }
}
})

driver:run()
