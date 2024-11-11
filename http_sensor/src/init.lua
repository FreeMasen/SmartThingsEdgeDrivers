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
local ColorTemp = capabilities.colorTemperature

local function is_bridge(device)
    return device:supports_capability_by_id(targetCountId)
end

local function sensor_profile_name(device)
  if device:supports_capability_by_id(ColorTemp.ID) then
    return "http_sensor-ext.v1"
  end
  return "http_sensor.v1"
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
    driver:emit_state(device, state)
    driver:send_to_all_sse({
      event = "init",
      device_id = device.id,
      device_name = device.label,
      state = state,
    })
  end

end

local function device_removed(driver, device)
  log.trace('Removed http_sensor ' .. device.id)
  driver:send_to_all_sse({
    event = "removed",
    device_id = device.id,
  })
end

local function info_changed(driver, device, event, args)
  log.trace('Info Changed ', device.id, args.old_st_store.profile.id, device.profile.id)
  -- Check if the old profile is the same as the new profile by ID, note that these
  -- id values do not have the same ID value as `st deviceprofile`...
  if args.old_st_store.profile.id ~= device.profile.id then
    local event = driver:get_sensor_state(device)
    event.event = "profile"
    driver:send_to_all_sse(event)
  end
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

local function  do_set_level(driver, device, args)
  print("do_set_level", device.id, utils.stringify_table(args, "args", true))
  device:emit_event(capabilities.switchLevel.level(args.args.level))
  driver:send_all_states_to_sse(device, {switch_level = args.args.level})
end

local function  set_color_temp_handler(driver, device, args)
  print("set_color_temp_handler", device.id, utils.stringify_table(args, "args", true))
  device:emit_event(capabilities.colorTemperature.colorTemperature(args.args.temp))
  -- driver:send_all_states_to_sse(device, {switch_level = args.args.level})
end

local driver = Driver(require("driver_name"), {
  lifecycle_handlers = {
    init = device_init,
    added = device_init,
    removed = device_removed,
    infoChanged = info_changed
  },
  discovery = discovery.disco_handler,
  driver_lifecycle = function()
    os.exit()
  end,
  capability_handlers = {
    [createTargetId] = {
      ["create"] = function(driver, device)
        log.info("createTarget")
        discovery.add_sensor_device(driver, nil, driver.bridge_id)
      end
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.switch.ID] = {
      
      [capabilities.switch.commands.on.NAME] = function(driver, device)
        driver:emit_state(device, {switch = "on"})
      end,
      [capabilities.switch.commands.off.NAME] = function(driver, device)
        driver:emit_state(device, {switch = "off"})
      end,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = do_set_level,
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temp_handler,
    },
  }
})

function Driver:send_all_states_to_sse(device, supp)
  self:send_to_all_sse({
    event = "update",
    device_id = device.id,
    device_name = device.label,
    profile = sensor_profile_name(device),
    state = supp or self:get_state_object(device)
  })
end


function Driver:send_to_all_sse(event)
  local not_closed = {}
  for i, tx in ipairs(self.sse_txs) do
    print("sending event to tx ", i)
    local _, err = tx:send(event)
    if err ~= "closed" then
      table.insert(not_closed, tx)
    end
  end
  self.sse_txs = not_closed

end

function Driver:get_state_object(device)
  print("Driver:get_state_object")
  local temp = device:get_latest_state("main", TemperatureMeasurement.ID,
    TemperatureMeasurement.temperature.NAME)
  if type(temp) == "number" then
      temp = {
          value = temp,
          unit = "F",
      }
  end
  
  local ret = {
    temp = temp,
    contact = device:get_latest_state("main", ContactSensor.ID, ContactSensor.contact.NAME),
    air = device:get_latest_state("main", AqSensor.ID, AqSensor.airQuality.NAME),
    switch = device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME),
    switch_level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.NAME),
  }
  local needs_color_temp = device:supports_capability_by_id(ColorTemp.ID)
  if needs_color_temp then
    ret.color_emp = device:get_latest_state("main", ColorTemp.ID, ColorTemp.colorTemperature.NAME)
  end
  local expected_props = {
    temp = {
          value = 50,
          unit = "F",
      },
    contact = "closed",
    air = 50,
    switch = "off",
    switch_level = 50,
  }
  if needs_color_temp then
    expected_props.color_temp = 1
  end
  for prop, default in pairs(expected_props) do
    if ret[prop] == nil then
      print(string.format("WARNING %q was nil, setting to default", prop))
      ret[prop] = default
    end
  end
  print("returning state", utils.stringify_table(ret))
  return ret
end

function Driver:emit_state(device, state)
  self:emit_sensor_state(device, state)
  self:emit_switch_state(device, state)
  self:send_all_states_to_sse(device)
end

function Driver:emit_sensor_state(device, state)
  if state.temp then
    device:emit_event(TemperatureMeasurement.temperature(state.temp or {
      value = 60,
      unit = "F"
    }))
  end
  if state.contact then
    device:emit_event(ContactSensor.contact(state.contact or "closed"))
  end
  if state.air then
    device:emit_event(AqSensor.airQuality(state.air or 50))
  end
end

function Driver:emit_switch_state(device, state)
  print("Driver:emit_switch_state", utils.stringify_table(state, "state", true))
  if state.switch == "on" then
    print("emitting on for ", device.label)
    device:emit_event(capabilities.switch.switch.on())
  elseif state.switch == "off" then
    print("emitting off for ", device.label)
    device:emit_event(capabilities.switch.switch.off())
  end
  if state.level then
    print("emitting level", state.level, " for ", device.label)
    device:emit_event(capabilities.switchLevel.level(state.level))
  end
  if device:supports_capability_by_id(ColorTemp.ID)
  and state.colorTemp
  then
    device:emit_event(ColorTemp.colorTemperature(state.colorTemp or 0))
  end
end

function Driver:get_url()
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

function Driver:get_sensor_states()
  local devices_list = {}
  for _, device in ipairs(driver:get_devices()) do
    if not is_bridge(device) then
      local state = self:get_sensor_state(device)
      table.insert(devices_list, state)
    end
  end
  return devices_list
end

function Driver:get_sensor_state(device)
  print("Driver:get_sensor_state", device.label or device.id)
  if is_bridge(device) then
    print("device is a bridge!")
    return nil, "device is bridge"
  end
  print("getting state object")
  local state = self:get_state_object(device)
  return {
    device_id = device.id,
    device_name = device.label,
    profile = sensor_profile_name(device),
    state = state
  }
end

function driver:emit_current_url()
  local url = self:get_url()
  local bridge
  for i, device in ipairs(self:get_devices()) do
    if device:supports_capability_by_id(currentUrlID) then
      self.bridge_id = device.id
      bridge = device
      break
    end
  end
  if url and bridge then
    bridge:emit_event(currentUrl.currentUrl(url))
  end
end

function driver:check_store_size()
  local json = require("st.json")
  local store_value = self.datastore:get_serializable()
  local store_str = json.encode(store_value)
  return #store_str, store_str
end

driver.sse_txs = {}

driver:call_with_delay(0, function(driver)
  while true do
    driver:emit_current_url()
    cosock.socket.sleep(10)
  end
end)


server(driver)

driver:run()
