
local caps = require "st.capabilities"
local Driver = require "st.driver"
local utils = require "st.utils"

local log = require "log"
local json = require "dkjson"
local cosock = require "cosock"

local task = require "task"
local disco = require "discovery"

local device_type_to_profile = {
  hub = "myq-proxy-hub.v1",
  light = "myq-proxy-light.v1",
  garagedoor = "myq-proxy-garagedoor.v1"
}

local parentDeviceId

local function find_device_by_dni(driver, dni)
  local devices = driver.device_api.get_device_list()
  for _,device in ipairs(devices) do
    if device.deviceNetworkId == dni then
      return device
    end
  end
end

local function create_device(driver, device_info)
  log.debug("creating a device", label, profile)
  local deviceNetworkId = device_info.id
  local profileReference = assert(device_type_to_profile[device_info.type], "unknown device type " ..device_info.type)
  local device_info = {
      type = "LAN",
      deviceNetworkId = device_info.id,
      label = device_info.name,
      profileReference = profileReference,
      vendorProvidedName = device_info.name,
      parentDeviceId = device_info.parent_id,
  }
  local device_info_json = json.encode(device_info)
  assert(driver.device_api.create_device(device_info_json))
end

local function disco(driver, opts, cont)
  print("starting disco", cont)
  local s, val, rip, rport
  if cont() then
    s, val, rip, rport = disco.find_devices(s)
    if not val then
      return log.error("failed to find devices ", rip)
    end
    local device_info = json.decode(val)
    local device = findDeviceByDni(driver, device_info.id)
    if not device then
      create_device(driver, device_info)
    end
  end
end

local function interface_task_tick(driver, dev_rx)
  local ev, err = dev_rx:receive()
  if not ev then
    return log.error("Error in dev_rx:receive", err)
  end
  log.trace("task sent message")
  if (ev or {}).kind == "presence-change" then
    log.debug(ev.kind, ev.id, ev.is_present)
    local device = driver:get_device_info(ev.id)
    if not device then
      return log.error("Unknown device id", ev.id)
    end
    local event_ctor
    if ev.is_present then
      event_ctor = caps.presenceSensor.presence.present
    else
      event_ctor = caps.presenceSensor.presence.not_present
    end
    device:emit_event(event_ctor())
  else
    -- log.debug("Unknown event", utils.stringify_table(ev, "Event", true))
  end
end

local function spawn_presence_interface_task(driver, dev_rx)
  cosock.spawn(function()
    while true do
      interface_task_tick(driver, dev_rx)
    end
  end)

end

local function init(driver, device)
  
end

local function emit_light_state(device, is_on)
  local ev
  if is_on then
    ev = caps.switch.switch.on()
  else
    ev = caps.switch.switch.off()
  end
  device:emit_event(on)
end

local garagedoor_states = {
  open = caps.doorControl.doorControl.open,
  opening = caps.doorControl.doorControl.opening,
  closed = caps.doorControl.doorControl.closed,
  closing = caps.doorControl.doorControl.closing,
  unknown = caps.doorControl.doorControl.unknown,
}

local function emit_door_state(device, new_state)
  local ev = (garagedoor_states[new_state]
              or caps.doorControl.doorControl.unknown)()
  device:emit_event(ev)
end

local function info_changed(driver, device)
  
end

local driver = Driver("MyQ Proxy", {
  discovery = disco,
  lifecycle_handlers = {
    init = init,
    added = init,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [caps.switch.ID] = {
      [caps.switch.commands.on.NAME] = function(driver, device)
          log.info('Turn on')
      end,
      [caps.switch.commands.off.NAME] = function(...)
        log.info('Turn Off')
      end,
    },
    [caps.doorControl.ID] = {
      [caps.doorControl.close.NAME] = function(driver, device)
        log.info("Close")
      end,
      [caps.doorControl.open.NAME] = function(driver, device)
        log.info("Open")
      end,
    }
  }
})

driver:run()
