local Driver = require 'st.driver'
local log = require 'log'
local utils = require 'st.utils'
local json = require 'dkjson'
local capabilities = require 'st.capabilities'
local cosock = require 'cosock'

-- Emit the switch state for a device
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

-- Discover exactly 1 device to prevent the runner from getting torn down
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

-- Device added handler, since we only expect 1 device to be associated with
-- this driver, this will create a cosock task and use 2 cosock.channel pairs
-- to communicate, registering 1 of the receivers with `Driver:register_channel_handler`
local function device_added(driver, device)
  if driver.task_tx then
    return log.warn("duplicate drvice added event")
  end
  -- Emit the current state to make sure the mobile app doesn't report it being disconnected
  emit_state(driver, device, {command = "off"})
  local task_tx, task_rx = cosock.channel.new()
  local device_tx, device_rx = cosock.channel.new()
  -- Delay the event from the spawned task to once every 60 seconds
  task_rx:settimeout(60)
  -- register the device_rx as a channel to be handled
  driver:register_channel_handler(device_rx, function()
    log.debug("Device message")
    -- receive the next event
    local msg, err = device_rx:receive()
    if msg then
      log.debug("message from device", msg)
    else
      log.error("Error from device_rx", err)
    end
    log.debug("exiting channel handler")
  end)
  -- store the sender for device capability events
  driver.task_tx = task_tx
  cosock.spawn(function()
    -- loop forever
    while true do
      -- receive a message or timeout at 60 seconds
      local ev, err = task_rx:receive()
      -- if no event, we have an error (probably "timeout")
      if not ev then
        log.error("Error from task_rx", err)
      else
        log.debug(string.format("event from driver: %s", utils.stringify_table(ev)))
      end
      -- Send on the device_tx to ensure that we can execute our channel_handler
      device_tx:send(string.format("Event from %s", os.time()))
    end
  end)
  log.debug("exiting device_added")
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
