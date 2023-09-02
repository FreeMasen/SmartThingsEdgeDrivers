local Driver = require 'st.driver'
local log = require 'log'
local capabilities = require 'st.capabilities'
local utils = require "st.utils"
local DRIVER_NAME = "cap-tester"
local json = require "st.json"

local job_file = capabilities["honestadmin11679.jobFile"]
local job_percent = capabilities["honestadmin11679.jobPerent"]
local job_time_rem = capabilities["honestadmin11679.jobTimeRemaining"]
local temp_set = capabilities["honestadmin11679.temperatureSetPoint"]
local temp_value = capabilities["honestadmin11679.temperature"]

local function disco(driver, opts, cont)
  print("starting disco", utils.stringify_table(opts))
  local device_list = driver.device_api.get_device_list()
  if not next(device_list) and cont() then
    print("discovering a device")
    local device_info = {
      type = "LAN",
      deviceNetworkId = string.format("%s", os.time()),
      label = "cap-tester",
      profileReference = "cap-tester.v1",
      vendorProvidedName = "cap-tester",
    }
    local device_info_json = json.encode(device_info)
    assert(driver.device_api.create_device(device_info_json))
  end
end

local function print_obj(name, obj)
  print(utils.stringify_table(obj, name, true))
end

local function emit_event(device, name, event_ctor, ...)
  print("emitting", name)
  local s, ev = pcall(event_ctor, ...)
  if not s then
    print(string.format("Failed to genenrate event for %s", name))
    return
  end
  print_obj(name, ev)
  local s = pcall(device.emit_event, device, ev)
  print(string.format("%s to emit %s", (s and "success") or "failed", name))
end

local function emit_caps(driver, device)
  -- print_obj("job_file", job_file)
  -- print_obj("job_percent", job_file)
  -- print_obj("job_time_rem", job_time_rem)
  -- print_obj("temp_set", temp_set)
  -- print_obj("temp_value", temp_value)

  
  emit_event(device, "job_file", job_file.jobFile, "hello.gcode")
  -- device:emit_event(job_file.jobFile("hello.gcode"))
  emit_event(device, "job_percent", job_percent.jobPercent, math.random(0, 100))
  -- device:emit_event(job_percent.jobPercent(math.random(0, 100)))
  -- local ev = job_time_rem({
  --   hours = math.random(0, 48),
  --   minutes = math.random(0, 60),
  --   seconds = math.random(0, 60),
  -- })
  print_obj("time-remaining ev", ev)
  device:emit_event(ev)
  -- device:emit_event(temp_set.temperatureSetPoint(math.random(0, 300)))
  -- device:emit_event(temp_value.temperature(math.random(0, 300)))
end
local driver = Driver(DRIVER_NAME, {
  discovery = disco,
  lifecycle_handlers = {
    init = emit_caps,
    added = emit_caps,
    infoChanged = emit_caps,
  },
  driver_lifecycle = function()
    os.exit()
  end
})


driver:run()
