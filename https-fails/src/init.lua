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
        label = 'https-fails',
        profileReference = 'https-fails.v1',
        vendorProvidedName = 'https-fails',
    }
    local device_info_json = json.encode(device_info)
    assert(driver.device_api.create_device(device_info_json))
  end
end

function _req(http, device)
  local ip_addr = device.preferences.ipAddr
  if not (type(ip_addr) == "string" and #ip_addr) then
    return log.warn("No ipAddr in preferences")
  end
  local response, status, headers, status_msg = 
   http.request(string.format("https://%s", ip_addr))
  if status == 200 then
    return log.info("Success!")
  end
  log.debug(string.format("Status: %q - %q", status, status_msg))
  log.debug(utils.stringify_table(headers, "Headers", true))
  if type(response) == "string" and #response > 0 then
    print("Response: %q", response)
  end
end

function make_request(device)
  log.trace("make_request")
  _req(socket.asyncify "socket.http", device)
end

function make_request2(device)
  log.trace("make_request2")
  _req(socket.asyncify "ssl.https", device)
end
local is_two = false
function emit_state(driver, device)
  log.debug('Emitting state')
  device:emit_event(capabilities.switch.switch.off())
  local req = make_request
  if is_two then
    req = make_request2
  end
  is_two = not is_two
  socket.spawn(function()
    req(device)
  end)
end

local driver = Driver('https-fails', {
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
