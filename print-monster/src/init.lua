local Driver = require 'st.driver'
local json = require 'st.json'
local log = require 'log'
local capabilities = require 'st.capabilities'
local cosock = require "cosock"

local function disco(driver, opts, cont)
  local device_list = driver.device_api.get_device_list()
  if not next(device_list) and cont() then
    print('discovering a device')
    local device_info = {
        type = 'LAN',
        deviceNetworkId = string.format('%s', os.time()),
        label = 'Monster',
        profileReference = 'print_monster.v1',
        vendorProvidedName = 'Monster',
    }
    local device_info_json = json.encode(device_info)
    assert(driver.device_api.create_device(device_info_json))
  end
end

local function task_that_runs_for(seconds, device, cap)
    local is_on = device.state_cache.main.switch.on and true or false
    return function()
        local start = cosock.socket.gettime()
        while cosock.socket.gettime() - start < seconds do
            if is_on then
                device:emit_event(capabilities.switch.switch.off())
            else
                device:emit_event(capabilities.switch.switch.on())
            end
            log.info("printing", start, is_on)
            is_on = not is_on
        end
    end
end

local function emit_state(driver, device)
  log.debug('Emitting state')
  local iter = (device.preferences or {}).printCount or 100
  
  for i=1,25 do
    cosock.spawn(task_that_runs_for(iter, device))
  end
end


local driver = Driver('Print Monster', {
  discovery = disco,
  lifecycle_handlers = {
    init = emit_state,
    added = emit_state,
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
