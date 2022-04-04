local cosock = require 'cosock'

local Driver = require 'st.driver'
local api = cosock.asyncify 'api'
local caps = require 'st.capabilities'
local log = require 'log'
local disco = require 'disco'
local utils = require 'st.utils'
local createCapID = "honestadmin11679.targetcreate"
local createTarget = caps[createCapID]
local displayCapID = "honestadmin11679.targetCount"
local display = caps[displayCapID]
local presence = require 'presence'

local PRESENT = caps.presenceSensor.presence.present
local NOT_PRESENT = caps.presenceSensor.presence.not_present

local TARGET_PROFILE = 'dream-presence-target.v1'
local parentDeviceId

local function device_is_parent(dev)
  return dev and dev:supports_capability_by_id(createCapID)
end

local function is_device_present(device)
  local value = device:get_latest_state('main', 'presenceSensor', 'presence', NOT_PRESENT.NAME)
  return value == PRESENT.NAME
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
      return dev
    end
  end
end

local function emit_target_count(driver, parentDevice)
  log.trace("emit_target_count")
  if not parentDevice then
    parentDevice = lookup_parent(driver)
    if not parentDevice then
      log.debug("No parent device found")
      return
    end
  end
  local dev_ids = driver:get_devices() or {""}
  log.debug("Emitting target count ", #dev_ids - 1)
  local ev = display.targetCount(math.max(#dev_ids - 1, 0))
  parentDevice:emit_event(ev)
end

local function handle_state_change(ch, driver)
  log.trace("handle_state_change")
  local state_change = assert(ch:receive())
  log.debug(utils.stringify_table(state_change, "state_change", true))
  log.debug(string.format("%s -> %s", state_change.device_id, state_change.state))
  local device = driver:get_device_info(state_change.device_id)
  local last = is_device_present(device)
  local event
  if state_change.state then
    if not last then
      event = PRESENT
    end
  else
    if last then
      event = NOT_PRESENT
    end
  end
  if event then
    device:emit_event(event())
  end
end

local function handle_parent_device_added(driver, device)
  log.trace("handle_parent_device_added")
  parentDeviceId = device.id
  emit_target_count(driver, device)
  local device_names = {}
  log.debug("Setting up initial devices")
  local devices = driver:get_devices()
  for _, child in ipairs(devices) do
    if child.preferences.clientname and #child.preferences.clientname > 0 then
      local current_state = is_device_present(child)
      log.debug(string.format("%s=> %s", child.id, current_state))
      device_names[child.preferences.clientname] = {
        id = child.id,
        state = current_state,
      }
    end
  end
  log.debug("Spawning presence task")
  local update_tx, event_rx = presence.spawn_presence_task(
    device.preferences.udmip, device_names, device.preferences.username,
    device.preferences.password, device.preferences.timeout
  )
  driver.update_tx = update_tx
  log.debug("Registering state change event handler")
  driver.event_listener = driver:register_channel_handler(event_rx, function()
    handle_state_change(event_rx, driver)
  end, "device updates")
end


local function handle_child_device_added(driver, device)
  log.trace("handle_child_device_added", device.preferences.clientname or "unknown target")
  if device.preferences.clientname and #device.preferences.clientname > 0 then
    if not driver.update_tx then
      log.debug("Attempt to add child device w/o update_tx")
      return
    end
    local initial_state = is_device_present(device)
    driver.update_tx:send(presence.new_client_message(
      device.id, device.preferences.clientname, initial_state
    ))
  end
end

---Validates the device preferences and then starts the poll
---@param driver Driver
---@param device Device
local function device_added(driver, device)
  log.trace('device added')
  if device_is_parent(device)then
    handle_parent_device_added(driver, device)
  else
    handle_child_device_added(driver, device)
  end
  emit_target_count(driver)
end

---Stop a poll loop when the device is removed
---@param driver Driver
---@param device Device
local function device_removed(driver, device)
  device:set_field("running", false)
  emit_target_count(driver)
end

---When a preference update comes down, stop any existing poll loop
---and start a new one if the preferences are populated
---@param driver Driver
---@param device Device
local function info_changed(driver, device)
  if device_is_parent(device) then
    driver.update_tx:send({
      type = "credentials-update",
      username = device.preferences.username,
      password = device.preferences.password,
      ip = device.preferences.udmip,
      timeout = device.preferences.timeout,
    })
    return
  end
  device_added(driver, device)
end

local driver = Driver('Dream Presence', {
  lifecycle_handlers = {
    init = device_added,
    added = device_added,
    removed = device_removed,
    infoChanged = info_changed,
  },
  discovery = disco.disco,
  capability_handlers = {
    [createTarget.ID] = {
      [createTarget.commands.create.NAME] = function (driver, device)
          disco.add_device(driver, 'Dream Presence Target', TARGET_PROFILE, device.id)
      end
    }
  }
})

driver:run()
