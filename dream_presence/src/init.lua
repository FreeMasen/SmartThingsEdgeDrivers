local cosock = require 'cosock'

local Driver = require 'st.driver'
local api = cosock.asyncify 'api'
local caps = require 'st.capabilities'
local log = require 'log'
local disco = require 'disco'
local utils = require 'st.utils'
local parentCapID = "honestadmin11679.targetcreate"
local createTarget = caps[parentCapID]

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
  log.trace('start_poll', utils.stringify_table(device.preferences, 'preferences', true))
  cosock.spawn(function()
    local cookie, xsrf
    while has_keys(driver.datastore, 'username', 'password', 'ip')
    and not is_nil_or_empty_string(device.preferences.clientname)
    and device:get_field('running') do
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
      local is_present, err = api.check_for_presence(ip, client, cookie, xsrf)
      if err then
        cookie, xsrf = nil, nil
        goto continue
      end
      local event
      local last = device:get_latest_state('main', 'presenceSensor', 'presence')
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

---Validates the device preferences and then starts the poll
---@param driver Driver
---@param device Device
local function device_added(driver, device)
  log.trace('device added', device.id, not not device.profile.components.main.capabilities[parentCapID])
  if not not device.profile.components.main.capabilities[parentCapID] then
    parentDeviceId = device.id
    log.trace('found parent device')
    if not has_keys(device.preferences, 'username', 'password', 'udmip') then
      log.debug('missing preference')
      log.debug('username', device.preferences.username)
      log.debug('ip', device.preferences.udmip)
      log.debug('password', (device.preferences.password and 'is set') or 'is unset')
      return
    end
    log.trace('setting global config options')
    driver.datastore.username = device.preferences.username
    driver.datastore.password = device.preferences.password
    driver.datastore.ip = device.preferences.udmip
    driver.datastore:save()
    log.trace('spawning any non-running polls')
    for _, child in ipairs(driver:get_devices()) do
      if not child:get_field('running') then
        if child.id ~= parentDeviceId then
          start_poll(driver, child)
          device:set_field("running", true)
        end
      end
    end
    return
  end
  device:set_field("running", true)
  start_poll(driver, device)
end

---Stop a poll loop when the device is removed
---@param driver Driver
---@param device Device
local function device_removed(driver, device)
  device:set_field("running", false)
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

-- server(driver)

-- cosock.spawn(function()
--   upnp(driver)
-- end)

driver:run()
