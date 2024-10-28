local Driver = require 'st.driver'
local json = require 'st.json'
local log = require 'log'
local capabilities = require 'st.capabilities'
local cosock = require "cosock"

local function disco(driver, opts, cont)
  while (cont()) do
    local device_list = driver.device_api.get_device_list()
    if #device_list < 40 then
      print('discovering a device')
      local device_info = {
          type = 'LAN',
          deviceNetworkId = string.format('%s', os.time()),
          label = 'Monster ' .. tostring(#device_list),
          profileReference = 'print_monster.v1',
          vendorProvidedName = 'Monster ' .. tostring(#device_list),
      }
      local device_info_json = json.encode(device_info)
      assert(driver.device_api.create_device(device_info_json))
      cosock.socket.sleep(1)
    else
      break
    end
  end
end

local function toggle_state(device)
  local is_on = (((device.state_cache or {}).main or {}).switch or {}).on and true or false
  if is_on then
    device:emit_event(capabilities.switch.switch.off())
  else
    device:emit_event(capabilities.switch.switch.on())
end

end


local function task_that_runs_for(seconds, device, cap)
    local is_on = (((device.state_cache or {}).main or {}).switch or {}).on and true or false
    return function()
        local start = cosock.socket.gettime()
        while cosock.socket.gettime() - start < seconds do
            toggle_state(device)
            log.info("printing", start, is_on)
            is_on = not is_on
        end
    end
end

local function emit_state(driver, device)
  log.debug('Emitting state')
  local iter = (device.preferences or {}).printCount or 100
  toggle_state(device)
  cosock.spawn(task_that_runs_for(iter, device))
end

local function init_device(driver, device)
  log.trace("init", device.id)
  toggle_state(device)
  local iter = (device.preferences or {}).printCount or 100
  for i=1,iter do
    log.info("printing", i)
  end
end


local driver = Driver('Print Monster', {
  discovery = disco,
  lifecycle_handlers = {
    init = init_device,
    added = function(_, device)
      log.trace("added", device.id)
      toggle_state(device)
    end,
    deleted = function() log.debug("device deleted") end,
  },
  driver_lifecycle = function()
    os.exit()
  end,
  capability_handlers = {
    [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = function(...)
            log.info('Turn on')
            emit_state(...)
        end,
        [capabilities.switch.commands.off.NAME] = function(...)
          log.info('Turn Off')
          emit_state(...)
        end
    }
}
})

driver:run()
