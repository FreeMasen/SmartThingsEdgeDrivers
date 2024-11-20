
local Driver = require 'st.driver'
local log = require 'log'
local json = require 'dkjson'
local caps = require 'st.capabilities'
local cosock = require 'cosock'
local task = require "task"
local createCapID = "honestadmin11679.targetcreate"
local createTarget = caps[createCapID]
local displayCapID = "honestadmin11679.targetCount"
local display = caps[displayCapID]
local utils = require "st.utils"


local parentDeviceId

local function device_is_parent(dev)
  return dev and dev:supports_capability_by_id(createCapID)
end


local function lookup_parent(driver)
  log.debug("lookup_parent")
  if parentDeviceId and parentDeviceId ~= "" then
    local parent = driver:get_device_info(parentDeviceId)
    if device_is_parent(parent) then
      return parent
    end
  end
  for _, dev in ipairs(driver:get_devices()) do
    if device_is_parent(dev) then
      parentDeviceId = dev.id
      return dev
    end
  end
end

local function emit_target_count(driver, device)
  log.trace("emit_target_count")
  if not device then
    return log.warn("no device provided")
  end
  local dev_ids = driver:get_devices() or {""}
  log.debug("Emitting target count ", #dev_ids - 1)
  local ev = display.targetCount(math.max(#dev_ids - 1, 0))
  device:emit_event(ev)
end

local function create_device(driver, label, profile, parentDeviceId)
  log.debug("creating a device", label, profile)
  local device_info = {
      type = "LAN",
      deviceNetworkId = string.format('%s', os.time()),
      label = label,
      profileReference = profile,
      vendorProvidedName = label,
      parentDeviceId = parentDeviceId,
  }
  local device_info_json = json.encode(device_info)
  assert(driver.device_api.create_device(device_info_json))

end

local function disco(driver, opts, cont)
  print('starting disco', cont)
  local device_list = driver.device_api.get_device_list()
  if not next(device_list) and cont() then
    create_device(driver, "mdns-presence", "mdns-presence.v1")
  end
end

local function emit_state(driver, device)
  log.debug('Emitting state')
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
  -- driver:register_channel_handler(dev_rx, function()
  --   interface_task_tick(driver, dev_rx)
  -- end)
  cosock.spawn(function()
    while true do
      interface_task_tick(driver, dev_rx)
    end
  end)

end

local function init(driver, device)
  if device_is_parent(device) then
    parentDeviceId = device.id
    if driver.task_tx ~= nil then
      return log.warn("Duplicate parent device?")
    end
    local task_tx, task_rx = cosock.channel.new()
    driver.task_tx = task_tx
    local dev_tx, dev_rx = cosock.channel.new()
    local devices = driver:get_devices()
    local task_devs = {}
    for _, child in ipairs(devices) do
      if child.preferences.clientname and #child.preferences.clientname > 0 then
        task_devs[child.preferences.clientname] = {
          last_seen = nil,
          id = child.id
        }
      end
    end
    task.spawn_presence_task({
      devices = task_devs,
      timeout = (device.preferences or {}).timeout or 5,
      away_trigger = (device.preferences or {}).awayTrigger or 60 * 5,
    }, dev_tx, task_rx)
    spawn_presence_interface_task(driver, dev_rx)
    emit_target_count(driver, device)
  else
    local prefs = device.preference or {}
    if prefs.clientname and #prefs.clientname > 0 then
        driver.task_tx:send({
          kind = "new-device",
          id = device.id,
          last_seen = nil,
          name = device.preferences.clientname,
        })
    end
  end
  emit_state(driver, device)
end

local function info_changed(driver, device)
  log.trace(utils.stringify_table(device.preferences, "Updated Preferences", true))
  if device_is_parent(device) then
    log.debug("parent device chaned")
  else
    local prefs = device.preferences or {}
    if prefs.clientname and #prefs.clientname > 0 then
      log.debug("sending")
        driver.task_tx:send({
          kind = "new-device",
          id = device.id,
          last_seen = nil,
          name = device.preferences.clientname,
        })
    end
  end

end

local driver = Driver('MDNS Presence', {
  discovery = disco,
  lifecycle_handlers = {
    init = init,
    added = init,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [createTarget.ID] = {
      [createTarget.commands.create.NAME] = function (driver, device)
        log.debug("create target pressed")
        local parent_dev = lookup_parent(driver)
        if not parent_dev then
          return log.error("Missing parent device")
        end
        create_device(driver, "mdns-presence-target", "mdns-presence-target.v1", parent_dev.id)
      end
    }
  }
})

driver:run()
