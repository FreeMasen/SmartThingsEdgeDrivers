local capabilities = require 'st.capabilities'
local Driver = require 'st.driver'
local log = require 'log'

local discovery = require 'disco'
local server = require 'server'
local utils = require 'st.utils'
local cosock = require 'cosock'

local currentUrlID = "honestadmin11679.currentUrl"
local currentUrl = capabilities[currentUrlID]

local createTargetId = "honestadmin11679.targetcreate"
local createTarget = capabilities[createTargetId];

local targetCountId = "honestadmin11679.targetCount"
local targetCount = capabilities[targetCountId]

local TemperatureMeasurement = capabilities.temperatureMeasurement
local ContactSensor = capabilities.contactSensor
local AqSensor = capabilities.airQualitySensor

local function is_bridge(device)
    return device:supports_capability_by_id(targetCountId)
end

local function device_init(driver, device)
  if is_bridge(device) then
    local dev_ids = driver:get_devices() or {""}
    log.debug("Emitting target count ", #dev_ids - 1)
    local ev = targetCount.targetCount(math.max(#dev_ids - 1, 0))
    device:emit_event(ev)
  else
    local state = driver:get_state_object(device)
    log.debug(utils.stringify_table(state, "state", true))
    driver:emit_sensor_state(device, state)
  end
end

local function device_removed(driver, device)
  log.trace('Removed http_sensor ' .. device.id)
end

local function info_changed(driver, device, event, ...)
  log.trace('Info Changed ', device.id, event, ...)
end

local function do_refresh(driver, device)
    -- If this is a sensor device, re-emit the stored state
    if not is_bridge(device) then
        device_init(driver, device)
        return
    end
    -- If this is a bridge device, re-emit the state for all devices
    for _,device in ipairs(driver:get_devices()) do
        if not is_bridge(device) then
            device_init(driver, device)
        end
    end
end

local driver = Driver('http_sensor', {
  lifecycle_handlers = {
    init = device_init,
    added = device_init,
    deleted = device_removed,
    infoChanged = info_changed
  },
  discovery = discovery.disco_handler,
  capability_handlers = {
    [createTargetId] = {
      ["create"] = function(driver, device)
        log.info("createTarget")
        discovery.add_device(driver, nil, driver.bridge_id)
      end
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  }

})

function Driver:get_state_object(device)
    local temp = device:get_latest_state("main", TemperatureMeasurement.ID,
      TemperatureMeasurement.temperature.NAME, {
        value = 60,
        unit = "F"
      })
    if type(temp) == "number" then
        temp = {
            value = temp,
            unit = "F",
        }
    end
    return {
      temp = temp,
      contact = device:get_latest_state("main", ContactSensor.ID, ContactSensor.contact.NAME,
        "closed"),
      air = device:get_latest_state("main", AqSensor.ID, AqSensor.airQuality.NAME, 50)
    }
end

function Driver:emit_sensor_state(device, state)
  device:emit_event(TemperatureMeasurement.temperature(state.temp or {
    value = 60,
    unit = "f"
  }))
  device:emit_event(ContactSensor.contact(state.contact or "closed"))
  device:emit_event(AqSensor.airQuality(state.air or 50))
end

function driver:get_url()
  if self.server == nil or self.server.port == nil then
    log.info('waiting for server to start')
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
    log.info(string.format('listening on %s', url))
  end
end

function driver:emit_current_url()
  local url = self:get_url()
  local bridge
  for i, device in ipairs(self:get_devices()) do
    if device:supports_capability_by_id(currentUrlID) then
      print("supports ", currentUrlID)

      self.bridge_id = device.id
      bridge = device
      break
    end
  end
  if url and bridge then
    bridge:emit_event(currentUrl.currentUrl(url))
  end
end

driver.ping_loop = driver:call_on_schedule(60, driver.print_listening_message)
driver:call_with_delay(0, function(driver)
  while true do
    driver:emit_current_url()
    cosock.socket.sleep(10)
  end
end)

server(driver)
driver:print_listening_message()

driver:run()
