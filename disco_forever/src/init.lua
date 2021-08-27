local Driver = require 'st.driver'
local log = require 'log'
local utils = require 'st.utils'
local cosock = require 'cosock'
local json = require 'dkjson'
local capabilities = require 'st.capabilities'

local function disco(driver, opts, cont)
  print('starting disco', cont)
  local device_list = driver.device_api.get_device_list()
  if not next(device_list) and cont() then
    print('discovering a device')
    local device_info = {
        type = 'LAN',
        deviceNetworkId = string.format('%s', os.time()),
        label = 'disco-forever',
        profileReference = 'disco-forever.v1',
        vendorProvidedName = 'disco-forever',
    }
    local device_info_json = json.encode(device_info)
    assert(driver.device_api.create_device(device_info_json))
  end
  local ct = 0
  while cont() do
    ct = ct + 1
    log.debug(ct, 'disco', utils.stringify_table(opts))
    cosock.socket.sleep(10)
  end
  log.debug('disco over', ct)
end

function emit_state(driver, device)
  log.debug('Emitting state from init or added')
  device:emit_event(capabilities.switch.switch.off())
end

local driver = Driver('Disco Forever', {
  discovery = disco,
  lifecycle_handlers = {
    init = emit_state,
    added = emit_state,
    deleted = function() log.debug("device deleted") end,
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = function(_, device)
            log.info('Turn on')
            device:emit_event(capabilities.switch.switch.on())
        end,
        [capabilities.switch.commands.off.NAME] = function(...)
          log.info('Turn Off')
          emit_state(...)
        end
    }
}
})

log.debug('Starting disco forever Driver')
driver:run()
