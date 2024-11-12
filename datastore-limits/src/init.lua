local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local json = require "st.json"
local log = require "log"

local discovery = require "disco"
local server = require "server"
local utils = require "st.utils"
local cosock = require "cosock"

local currentUrlID = "honestadmin11679.currentUrl"
local currentUrl = capabilities[currentUrlID]

local function fan_out_sse_message(driver, event)
  for _, tx in ipairs(driver.sse_txs or {}) do
    tx:send(event)
  end
end

local function see_event_with_state(device, event_type)
  local switch_state = device:get_latest_state("main", "switch", "switch", "off")
  return {
    event = event_type,
    device_id = device.id,
    device_name = device.label,
    state = {
      switch = switch_state,
    },
  }
end

local function append_to_log(log, activity)
  local key = string.format("%.05f", cosock.socket.gettime())
  log[key] = activity
end

local function log_driver_activity(driver, activity)
  local log = driver.datastore.driver_log or {}
  append_to_log(log, activity)
  driver.datastore.driver_log = log
end

local function log_device_activity(device, activity)
  local log = device:get_field("activity_log") or {}
  append_to_log(log, activity)
  device:set_field("activity_log", log, {
    persist = true,
  })
end

-- These handlers are primarily to make the log traffic
-- as chatty as possible
local function device_added(driver, device)
  local url = driver:get_url()
  if url then
    device:emit_event(currentUrl.currentUrl(url))
  end
  log_driver_activity(driver, "Added datastore_limits " .. device.id)
  fan_out_sse_message(driver, see_event_with_state(device, "added"))
end

local function device_init(driver, device)
  local url = driver:get_url()
  if url then
    device:emit_event(currentUrl.currentUrl(url))
  end
  log_driver_activity(driver, "Init\"d datastore_limits " .. device.id)
  fan_out_sse_message(driver, see_event_with_state(device, "init"))
end

local function device_removed(driver, device)
  log_driver_activity(driver, "Removed datastore_limits " .. device.id)
  fan_out_sse_message(driver, {
    event = "removed",
    device_id = device.id,
  })
end

local function info_changed(driver, device, event, ...)
  local event_parts = {"Info Changed", event}
  for _, arg in ipairs(table.pack(...)) do
    if type(arg) == "table" then
      for k, v in pairs(arg) do
        table.insert(event_parts, tostring(k))
        table.insert(event_parts, tostring(v))
      end
    else
      table.insert(event_parts, tostring(arg))
    end
  end
  log_device_activity(device, table.concat(event_parts, " "))
  table.insert(event_parts, 2, device.id)
  log_driver_activity(driver, table.concat(event_parts, " "))
  fan_out_sse_message(driver, see_event_with_state(device, "updated"))
end

local function emit_state(driver, device, on)
  log_driver_activity(driver, string.format("emitting state for %s -> %s", device.id,
                                            (on and "on") or "off"))
  local cap
  if on then
    cap = capabilities.switch.switch.on()
  else
    cap = capabilities.switch.switch.off()
  end
  device:emit_event(cap)
  log_device_activity(device, string.format("emitting state %s", (on and "on") or "off"))
  fan_out_sse_message(driver, see_event_with_state(device, "updated"))
end

local driver = Driver("datastore_limits", {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    deleted = device_removed,
    infoChanged = info_changed,
  },
  discovery = discovery.disco_handler,
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = function(driver, device)
        log.info("Turn on")
        emit_state(driver, device, true)
      end,
      [capabilities.switch.commands.off.NAME] = function(driver, device)
        log.info("Turn Off")
        emit_state(driver, device, false)
      end,
    },
  },
})

driver.emit_state = emit_state

function driver:get_url()
  if self.server == nil or self.server.port == nil then
    log.info("waiting for server to start")
    return
  end
  local ip = self.server:get_ip()
  local port = self.server.port
  if ip == nil then
    return
  end
  return string.format("http://%s:%s", ip, port)
end

--- Print the current listening IP and port number
function driver:print_listening_message()
  local url = self:get_url()
  if url then
    local states = {}
    for _, dev in pairs(self:get_devices()) do
      local state = dev:get_latest_state("main", "switch", "switch", "off")
      local activity = string.format("%s == %s", dev.id, state)
      table.insert(states, activity)
    end
    log_driver_activity(self, {
      current_url = url,
      states = states,
    })
    log.info(string.format("listening on %s", url))
  end
end

function driver:emit_current_url()
  local url = self:get_url()
  if url then
    for i, device in ipairs(self:get_devices()) do
      log_device_activity(device, string.format("listening on %s", url))
      device:emit_event(currentUrl.currentUrl(url))
    end
  else
    self:call_with_delay(1, self.emit_current_url)
  end
end

function driver:clear_log(device_id)
  if not device_id then
    driver.datastore.driver_log = {}
  else
    local device = driver:get_device_info(device_id)
    device:set_field("activity_log", {}, {
      persist = true,
    })
  end
end

driver.ping_loop = driver:call_on_schedule(60, driver.print_listening_message)
driver:call_with_delay(0, driver.emit_current_url)

driver.sse_txs = {}

server(driver)
driver:print_listening_message()

driver:run()
log.warn("Exiting datastore_limits")
