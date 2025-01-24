local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

local discovery = require "disco"
local server = require "server"
local utils = require "st.utils"
local cosock = require "cosock"

local currentUrlID = "honestadmin11679.currentUrl"
local currentUrl = capabilities[currentUrlID]

local createTargetId = "honestadmin11679.targetcreate"
local createTarget = capabilities[createTargetId];

local targetCountId = "honestadmin11679.targetCount"
local targetCount = capabilities[targetCountId]

local Time = capabilities.atmosphericPressureMeasurement
Time.time = Time.atmosphericPressure
local Switch = capabilities.switch

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
    device:emit_event(Switch.switch.off())
    device:emit_component_event(device.profile.components.expected,
                                Time.time(device.preferences.timeout or 1))
    driver:send_to_all_sse({
      event = "init",
      device_id = device.id,
      device_name = device.label,
      state = state,
    })
  end
end

local function device_removed(driver, device)
  log.trace("Removed http_sensor " .. device.id)
  driver:send_to_all_sse({
    event = "removed",
    device_id = device.id,
  })
end

local function info_changed(driver, device, event, args)
  log.trace("Info Changed ", device.id)
  local timer = device:get_field("timer")
  if timer then
    driver:cancel_timer(timer)
    device:set_field("timer", nil)
  end
  device:emit_component_event(device.profile.components.expected,
                              Time.time(device.preferences.timeout or 1))
  device:emit_event(Switch.switch.off())
end

local function do_refresh(driver, device)
  -- If this is a sensor device, re-emit the stored state
  if not is_bridge(device) then
    device_init(driver, device)
    return
  end
  -- If this is a bridge device, re-emit the state for all devices
  for _, device in ipairs(driver:get_devices()) do
    if not is_bridge(device) then
      device_init(driver, device)
    end
  end
end

local function timer_expired(driver, device)
  print("timer expired")
  local now = cosock.socket.gettime()
  local started = device:get_field("last-start")
  local elapsed = -1
  if started then
    elapsed = now - started
  end
  device:emit_component_event(device.profile.components.actual, Time.time(elapsed))
  driver:send_all_states_to_sse(device)
end


local function do_switch(driver, device, on)
  print("do_switch", device.id, utils.stringify_table(device.preferences))
  local ev = on and Switch.switch.on() or Switch.switch.off()
  device:emit_event(ev)
  print("emitted event")
  local existing_timer = device:get_field("timer")
  if existing_timer then
    print("canceling existing timer")
    driver:cancel_timer(existing_timer)
  end
  if on then
    local new_timer
    local to = math.max(device.preferences.timeout or 0, 1)
    device:set_field("last-start", cosock.socket.gettime())
    if device.preferences.interval then
      new_timer = device.thread:call_on_schedule(to, function()
        timer_expired(driver, device)
      end)
    else
      new_timer = device.thread:call_with_delay(to, function()
        timer_expired(driver, device)
        device:set_field("last-start", nil)
        device:emit_event(Switch.switch.off())
      end)
    end
    device:set_field("timer", new_timer)
  end
  driver:send_all_states_to_sse(device)
end

function Driver:get_bridge_id()
  if self.bridge_id and #self.bridge_id > 0 then
    return self.bridge_id
  end
  for _, device in ipairs(self:get_devices()) do
    if is_bridge(device) then
      self.bridge_id = device.id
      return self.bridge_id
    end
  end
  error("No devices were bridges!")
end

function Driver:send_all_states_to_sse(device, supp)
  self:send_to_all_sse({
    event = "update",
    device_id = device.id,
    device_name = device.label,
    state = supp or self:get_state_object(device),
  })
end

function Driver:emit_state(device, state)
  do_switch(self, device, state.switch == "on")
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
  return {
    switch = device:get_latest_state("main", Switch.ID, Switch.switch.NAME),
    timeout = device.preferences.timeout,
    interval = device.preferences.interval,
    last_duration = device:get_latest_state("actual", Time.ID, Time.time.NAME),
  }
end

function Driver:get_url()
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

function Driver:get_sensor_states()
  local devices_list = {}
  for _, device in ipairs(self:get_devices()) do
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
    state = state,
  }
end

function Driver:emit_current_url()
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

local driver = Driver(require("driver_name"), {
  lifecycle_handlers = {
    init = device_init,
    added = device_init,
    removed = device_removed,
    infoChanged = info_changed,
  },
  discovery = discovery.disco_handler,
  driver_lifecycle = function()
    os.exit()
  end,
  capability_handlers = {
    [createTargetId] = {
      ["create"] = function(driver, device)
        log.info("createTarget")
        discovery.add_timer_device(driver, nil, driver:get_bridge_id())
      end,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = function(driver, device)
        do_switch(driver, device, true)
      end,
      [capabilities.switch.commands.off.NAME] = function(driver, device)
        do_switch(driver, device, false)
      end,
    },
  },
})

driver.sse_txs = {}

cosock.spawn(function()
  local url, new_url, bridge_id, bridge
  while true do
    bridge_id = driver:get_bridge_id()
    if not bridge_id then
      goto continue
    end
    bridge = driver:get_device_info(bridge_id)
    if not bridge then
      goto continue
    end
    new_url = driver:get_url()
    if not new_url then
      goto continue
    end
    if new_url == url then
      goto continue
    end
    url = new_url
    bridge:emit_event(currentUrl.currentUrl(new_url))
    ::continue::
    cosock.socket.sleep(10)
  end
end)

server(driver)

driver:run()
