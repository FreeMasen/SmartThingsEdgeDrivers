local Driver = require 'st.driver'
local log = require 'log'
local utils = require 'st.utils'
local json = require 'dkjson'
local capabilities = require 'st.capabilities'
local socket = require 'cosock'

local function disco(driver, opts, cont)
  print('starting disco', utils.stringify_table(opts))
  local device_list = driver.device_api.get_device_list()
  if not next(device_list) and cont() then
    print('discovering a device')
    local device_info = {
        type = 'LAN',
        deviceNetworkId = string.format('%s', os.time()),
        label = 'debug-env',
        profileReference = 'debug-env.v1',
        vendorProvidedName = 'debug-env',
    }
    local device_info_json = json.encode(device_info)
    assert(driver.device_api.create_device(device_info_json))
  end
end

function emit_state(driver, device)
  log.debug('Emitting state')
  device:emit_event(capabilities.switch.switch.off())
end

local function debug_env(driver)
  log.debug(utils.stringify_table(_ENV, "_ENV", true))
  log.debug(utils.stringify_table(driver.environment_info, "driver.environment_info", true))
end

local driver = Driver('Debug Env', {
  discovery = disco,
  lifecycle_handlers = {
    init = emit_state,
    added = emit_state,
    deleted = function() log.debug("device deleted") end,
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = function(driver, device)
            log.info('Turn on')
            debug_env(driver)
            device:emit_event(capabilities.switch.switch.on())
        end,
        [capabilities.switch.commands.off.NAME] = function(...)
          log.info('Turn Off')
          emit_state(...)
        end
    }
}
})

log.debug('Starting debug env Driver')
debug_env(driver)
driver:run()
