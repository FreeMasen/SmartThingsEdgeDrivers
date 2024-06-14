local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local caps = require("st.capabilities")
local Driver = require("st.driver")
local utils = require("st.utils")

local log = require("log")
local json = require("st.json")
local cosock = require("cosock")

local task = require("task")
local disco_mod = require("discovery")







local device_type_to_profile = {
   hub = "myq-proxy-hub.v1",
   light = "myq-proxy-light.v1",
   garagedoor = "myq-proxy-garagedoor.v1",
}

local function find_device_by_dni(driver, dni)
   local devices = driver:get_devices()
   for _, device in ipairs(devices) do
      if device.deviceNetworkId == dni then
         return device
      end
   end
end









local function create_device(driver, device_info)
   log.debug("creating a device")
   local profileReference = assert(device_type_to_profile[device_info.type], "unknown device type " .. device_info.type)
   local parentDeviceId = nil
   if device_info.parent_device_id and
      #device_info.parent_device_id > 0 then
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
      parentDeviceId = parentDeviceId,
   }
   assert(driver:try_create_device(create_info))
end

local function disco(_driver, _opts, cont)
   print("starting disco", cont)
   local response, err = disco_mod.discover_proxy_server(cont)












end


























local function emit_light_state(device, is_on)
   local ev = nil
   if is_on then
      ev = caps.switch.switch.on()
   else
      ev = caps.switch.switch.off()
   end
   device:emit_event(ev)
end

local garagedoor_states = {
   open = caps.doorControl.doorControl.open,
   opening = caps.doorControl.doorControl.opening,
   closed = caps.doorControl.doorControl.closed,
   closing = caps.doorControl.doorControl.closing,
   unknown = caps.doorControl.doorControl.unknown,
}

local function emit_door_state(device, new_state)
   local ev = (garagedoor_states[new_state] or
   garagedoor_states.unknown)()
   device:emit_event(ev)
end

local function interface_task_tick(driver, dev_rx)
   local ev, err = dev_rx:receive()
   if not ev then
      log.error("Error in dev_rx:receive", err)
      return
   end
   ev = ev
   log.trace("task sent message")
   if ev.type == "StateChange" then
      local change = ev.change
      if change.kind == "deviceUpdate" then
         local device = find_device_by_dni(driver, change.device_id)
         if not device then
            log.warn("Unknown device state change", utils.stringify_table(ev, "ev", true))
            return
         end
         local state = change.device_type
         if state.kind == "garageDoor" then
            emit_door_state(device, state.state)
         elseif (change.device_type).kind == "lamp" then
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

local function spawn_presence_interface_task(driver, dev_rx)
   cosock.spawn(function()
      while true do
         interface_task_tick(driver, dev_rx)
      end
   end)

end

local function init(driver, device)

end


local function info_changed(driver, device)

end

local driver = Driver("MyQ Proxy", {
   discovery = disco,
   driver_lifecycle = {
      shutdown = function(_) end,
   },
   lifecycle_handlers = {
      init = init,
      added = init,
      infoChanged = info_changed,
   },
   capability_handlers = {
      [caps.switch.ID] = {
         [caps.switch.commands.on.NAME] = function(_driver, _device)
            log.info('Turn on')
         end,
         [caps.switch.commands.off.NAME] = function(_driver, _device)
            log.info('Turn Off')
         end,
      },
      [caps.doorControl.ID] = {
         [caps.doorControl.commands.close.NAME] = function(_driver, _device)
            log.info("Close")
         end,
         [caps.doorControl.commands.open.NAME] = function(_driver, _device)
            log.info("Open")
         end,
      },
   },
})

driver:run()
