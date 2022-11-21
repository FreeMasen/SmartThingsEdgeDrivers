
local caps = require "st.capabilities"
local Driver = require "st.driver"
local utils = require "st.utils"

local log = require "log"
local json = require "st.json"
local cosock = require "cosock"

local task = require "task"
local disco_mod = require "discovery"

local enum DeviceType
  "hub"
  "light"
  "garagedoor"
end

local device_type_to_profile = {
  hub = "myq-proxy-hub.v1",
  light = "myq-proxy-light.v1",
  garagedoor = "myq-proxy-garagedoor.v1"
}

local function find_device_by_dni(driver: Driver, dni: string): Driver.Device
  local devices = driver:get_devices()
  for _,device in ipairs(devices) do
    if device.deviceNetworkId == dni then
      return device
    end
  end
end

local record DeviceInfo
  serial_number: string
  type: DeviceType
  parent_device_id: string|nil
  name: string
  device_id: string
end

local function create_device(driver: Driver, device_info: DeviceInfo)
  log.debug("creating a device")
  local profileReference = assert(device_type_to_profile[device_info.type], "unknown device type " ..device_info.type)
  local parentDeviceId: string = nil
  if device_info.parent_device_id
  and #device_info.parent_device_id > 0 then
    local parent = find_device_by_dni(driver, device_info.parent_device_id)
    if parent then
      parentDeviceId = parent.device_id
    end
  end
  local create_info = {
      type = "LAN",
      deviceNetworkId = device_info.serial_number,
      label = device_info.name,
      profileReference = profileReference,
      vendorProvidedName = device_info.name,
      parentDeviceId = parentDeviceId
  }
  assert(driver:try_create_device(create_info))
end

local function disco(_driver: Driver, _opts: table, cont: function():boolean)
  print("starting disco", cont)
  local response, err = disco_mod.discover_proxy_server(cont)
  -- if cont() then
  --   val, rip, rport = disco.discover_proxy_server(s)

  --   if not val then
  --     return log.error("failed to find devices ", rip)
  --   end
  --   local device_info = json.decode(val)
  --   local device = findDeviceByDni(driver, device_info.id)
  --   if not device then
  --     create_device(driver, device_info)
  --   end
  -- end
end
local record WsEvent
  type: WsEventType
  change: StateChange|nil
end
local enum WsEventType
  "StateChange"
end
local enum StateChangeType
  "deviceAdded"
  "deviceUpdate"
  "deviceRemoved"
end

local record DeviceState
  kind: string
  state: string
end

local record StateChange
  kind: StateChangeType
  device_id: string
  device_type: DeviceState|nil
  device_details: DeviceInfo
end


local function emit_light_state(device: Driver.Device, is_on: boolean)
  local ev = nil as any
  if is_on then
    ev = caps.switch.switch.on()
  else
    ev = caps.switch.switch.off()
  end
  device:emit_event(ev)
end

local garagedoor_states: {string: function():any} = {
  open = caps.doorControl.doorControl.open,
  opening = caps.doorControl.doorControl.opening,
  closed = caps.doorControl.doorControl.closed,
  closing = caps.doorControl.doorControl.closing,
  unknown = caps.doorControl.doorControl.unknown,
}

local function emit_door_state(device: Driver.Device, new_state: string)
  local ev = (garagedoor_states[new_state]
              or garagedoor_states.unknown)()
  device:emit_event(ev)
end

local function interface_task_tick(driver: Driver, dev_rx: cosock.channel.ReceiveHalf<WsEvent>)
  local ev, err = dev_rx:receive()
  if not ev then
    log.error("Error in dev_rx:receive", err)
    return
  end
  ev = ev as WsEvent
  log.trace("task sent message")
  if ev.type == "StateChange" then
      local change = ev.change as StateChange
      if change.kind == "deviceUpdate" then
        local device = find_device_by_dni(driver, change.device_id)
        if not device then
          log.warn("Unknown device state change", utils.stringify_table(ev, "ev", true))
          return
        end
        local state = change.device_type as DeviceState
        if state.kind == "garageDoor" then
          emit_door_state(device, state.state)
        elseif (change.device_type as DeviceState).kind == "lamp" then
          emit_light_state(device, state.state == "on")
        end
      elseif change.kind == "deviceAdded" then
        create_device(driver, change.device_details)
      elseif change.kind == "deviceRemoved" then
        local device = find_device_by_dni(driver, change.device_id)
        if not device then
          log.warn("Unknown device remove", utils.stringify_table(ev, "ev", true))
          return
        end
    end
  end
end

local function spawn_presence_interface_task(driver: Driver, dev_rx: cosock.channel.ReceiveHalf<WsEvent>)
  cosock.spawn(function()
    while true do
      interface_task_tick(driver, dev_rx)
    end
  end)

end

local function init(driver: Driver, device: Driver.Device)
  
end


local function info_changed(driver: Driver, device: Driver.Device)
  
end

local driver = Driver("MyQ Proxy", {
  discovery = disco,
  driver_lifecycle = {
    shutdown = function(_: Driver)end
  },
  lifecycle_handlers = {
    init = init,
    added = init,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [caps.switch.ID] = {
      [caps.switch.commands.on.NAME] = function(_driver: Driver, _device: Driver.Device)
          log.info('Turn on')
      end,
      [caps.switch.commands.off.NAME] = function(_driver: Driver, _device: Driver.Device)
        log.info('Turn Off')
      end,
    },
    [caps.doorControl.ID] = {
      [caps.doorControl.commands.close.NAME] = function(_driver: Driver, _device: Driver.Device)
        log.info("Close")
      end,
      [caps.doorControl.commands.open.NAME] = function(_driver: Driver, _device: Driver.Device)
        log.info("Open")
      end,
    }
  }
})

driver:run()
