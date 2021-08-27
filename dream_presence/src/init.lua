local cosock = require 'cosock'

math.randomseed(cosock.socket.gettime()*10000)

local Driver = require 'st.driver'
local api = cosock.asyncify 'api'
local caps = require 'st.capabilities'
local json = require 'dkjson'
local log = require 'log'
local disco = require 'disco'
local server = cosock.asyncify 'server'

local PRESENT = caps.presenceSensor.presence.present()
local NOT_PRESENT = caps.presenceSensor.presence.not_present()



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
  log.trace('start_poll')
  local cookie, xsrf
  driver.poll_handles[device.id] = driver:call_on_schedule(5, function(driver)
    log.debug('polling');
    local ip, client, username, password =
      device.preferences.udmIp,
      device.preferences.clientName,
      device.preferences.username,
      device.preferences.password
    if not cookie or not xsrf then
      cookie, xsrf = api.login(ip, username, password)
      if not cookie then
        log.debug('Error logging in', xsrf)
        return
      end
    end
    local is_present, err = api.check_for_presence(ip, client, cookie, xsrf)
    if err then
      cookie, xsrf = nil, nil
      return
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
  end)
end
---Validates the device preferences and then starts the poll
---@param driver Driver
---@param device Device
local function device_added(driver, device)
  log.trace('device added', device.id)
  if not has_keys(device.preferences, 'username', 'password', 'clientName', 'udmIp') then
    return
  end
  start_poll(driver, device)
end

---Stop a poll loop when the device is removed
---@param driver Driver
---@param device Device
local function device_removed(driver, device)
  driver:cancel_timer(driver.poll_handles[device.id])
  driver.poll_handles[device.id] = nil
end

---When a preference update comes down, stop any existing poll loop
---and start a new one if the preferences are populated
---@param driver Driver
---@param device Device
local function info_changed(driver, device)
  if driver.poll_handles[device.id] then
    driver:cancel_timer(driver.poll_handles[device.id])
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
})

driver.poll_handles = {}

server(driver)

driver:run()
