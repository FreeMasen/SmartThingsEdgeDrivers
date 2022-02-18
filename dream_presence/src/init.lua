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

local PRESENT = caps.presenceSensor.presence.present()
local NOT_PRESENT = caps.presenceSensor.presence.not_present()

local TARGET_PROFILE = 'dream-presence-target.v1'
local parentDeviceId

---Check if a variable is nil or an empty string
---@param v string|nil
---@return boolean
local function is_nil_or_empty_string(v)
  if type(v) == 'string' then
    return #v == 0
  end
  return true
end

---Test if a table contains all provided keys
---@param t table
---@vararg string
---@return boolean
local function has_keys(t, ...)
  for _, key in ipairs({...}) do
    if is_nil_or_empty_string(t[key]) then
      log.error('missing key', key)
      return false
    end
  end
  log.debug('found all keys')
  return true
end

---Start the poll for the the presence of a hostname once the preferences are populated
---@param driver Driver
---@param device Device
local function start_poll(driver, device)
  log.trace(caps.get_capability_definition("honestadmin11679.targetCount", 1, true))
  log.trace('start_poll', utils.stringify_table(device.preferences, 'preferences', true))
  cosock.spawn(function()
    local cookie, xsrf
    while has_keys(driver.datastore, 'username', 'password', 'ip')
    and not is_nil_or_empty_string(device.preferences.clientname)
    and device:get_field('running') do
      local is_present, event, last, err
      log.debug(string.format('polling with cookie: %s with xsrf: %s', cookie ~= nil, xsrf ~= nil))
      local ip, client, username, password =
        driver.datastore.ip,
        device.preferences.clientname,
        driver.datastore.username,
        driver.datastore.password
      if not cookie or not xsrf then
        cookie, xsrf = api.login(ip, username, password)
        if not cookie then
          log.debug('Error logging in', xsrf)
          goto continue
        end
      end
      is_present, err = api.check_for_presence(ip, client, cookie, xsrf)
      if err then
        cookie, xsrf = nil, nil
        goto continue
      end
      last = device:get_latest_state('main', 'presenceSensor', 'presence')
      if is_present then
        if last ~= PRESENT.value.value then
          event = PRESENT
        end
      else
        if last ~= NOT_PRESENT.value.value then
          event = caps.presenceSensor.presence.not_present()
        end
      end
      if event then
        device:emit_event(event)
      end
      ::continue::
      cosock.socket.sleep(5)
    end
    device:set_field("running", false)
  end)
end

local function device_is_parent(dev)
  return dev and not not dev.profile.components.main.capabilities[createCapID]
end

local function lookup_parent(driver)
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
  if not parentDevice then
    parentDevice = lookup_parent(driver)
    if not parentDevice then
      log.warn("No parent device found")
      return
    end
  end
  local dev_ids = driver:get_devices() or {""}
  log.debug("Emitting target count ", #dev_ids - 1)
  local ev = display.targetCount(math.max(#dev_ids - 1, 0))
  parentDevice:emit_event(ev)
end

---Validates the device preferences and then starts the poll
---@param driver Driver
---@param device Device
local function device_added(driver, device)
  log.trace('device added', device.id, not not device.profile.components.main.capabilities[createCapID])
  if not not device.profile.components.main.capabilities[createCapID] then
    parentDeviceId = device.id
    log.trace('found parent device')
    emit_target_count(driver, device)
    local devices = driver:get_devices()
    local ready_to_poll = has_keys(device.preferences, 'username', 'password', 'udmip')
    if not ready_to_poll then
      log.debug('missing preference')
      log.debug('username', device.preferences.username)
      log.debug('ip', device.preferences.udmip)
      log.debug('password', (device.preferences.password and 'is set') or 'is unset')
    else
      log.trace('setting global config options')
      driver.datastore.username = device.preferences.username
      driver.datastore.password = device.preferences.password
      driver.datastore.ip = device.preferences.udmip
      driver.datastore:save()
      log.trace('spawning any non-running polls')
      for _, child in ipairs(devices) do
        if not child:get_field('running') then
          if child.id ~= parentDeviceId then
            start_poll(driver, child)
            device:set_field("running", true)
          end
        end
      end
    end
    return
  end
  emit_target_count(driver)
  device:set_field("running", true)
  start_poll(driver, device)
  print("started poll")
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
