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

function make_sse_req(ip)
  local EventSource = require "lunchbox.sse.eventsource"
  local url = string.format("https://%s:443/sse", ip)
  local eventsource = EventSource.new(
                            url,
                            nil
                          )

  eventsource.onmessage = function(msg)
    if msg and msg.data then
      print(utils.stringify_table(json.decode(msg.data) or {}, "msg-data", true))
    else
      print("msg with no data")
    end
  end
end
local function dbg(prefix, ...)
  print(prefix, ...)
  return ...
end
function make_lunchbox_req(ip)
  local Client = require "lunchbox.rest"
    local client = Client.new(string.format("https://%s:443", ip))
  cosock.spawn(function()
    make_sse_req(ip)
  end)
  for i=1,10 do
    print("req", i)
    
    local res = assert(dbg("res:", client:get(string.format("/%s", i)), {["keep-alive"] = "timeout=600", ["accept-encoding"] = "chunked"}))
    local body = assert(dbg("body:", res:get_body()))
    socket.socket.sleep(2)
  end

end

function _req(http, device)
  print("prefs:", utils.stringify_table(device.preferences, "prefs", true))
  local ip_addr = device.preferences.ipAddr
  if not (type(ip_addr) == "string" and #ip_addr > 0) then
    return log.warn("No ipAddr in preferences")
  end
  local url = string.format("https://%s:3030", ip_addr)
  print("requesting GET", url)
  local response, status, headers, status_msg = 
   http.request(url)
  if status == 200 then
    return log.info("Success!")
  end
  log.debug(string.format("Status: %q - %q", status, status_msg))
  log.debug(utils.stringify_table(headers or {}, "Headers", true))
  if type(response) == "string" and #response > 0 then
    print("Response: %q", response)
  end
end

function _make_manual_request(sock, ip)
  local Request = require "luncheon.request"
  local Response = require "luncheon.response"
  local lunch_utils = require "luncheon.utils"
  local req = Request.new("GET", string.format("https://%s:443/", ip), nil)
    :add_header("host", ip .. ":443")
    :add_header("connection", "keep-alive")
    -- :add_header("keep-alive", "timeout=600")
    :add_header("accept", "*/*")
    :add_header("content-length", "0")
  print(utils.stringify_table(req, "req", true))
  local msg = req:serialize()
  print(msg)
  local ct = assert(sock:send(msg))
  assert(ct == #msg)
  local res = Response.source(function(...) return sock:receive(...) end)
  print(res:get_body())
  print(utils.stringify_table(res or {}, "res", true))
end


function make_manual_request(ip)
  local cosock = require "cosock"
  local ssl = require "cosock.ssl"
  local sock = assert(cosock.socket.tcp())
  sock:settimeout(3)
  local _, err = sock:connect(ip, 443)
  sock = assert(ssl.wrap(sock, {mode = "client", protocol = "any", verify = "none", options = "all"}))
  assert(sock:dohandshake())
  local _sock_close = sock.close
  sock.close = function(self, ...)
    print("closing", debug.traceback())
    _sock_close()
  end
  for i=1, 10 do
    _make_manual_request(sock, ip)
  end
end

function make_request(device)
  log.trace("make_request")
  _req(socket.asyncify "socket.http", device)
end

function make_request2(device)
  log.trace("make_request2")
  local ip_addr = device.preferences.ipAddr
  if not (type(ip_addr) == "string" and #ip_addr > 0) then
    return log.warn("No ipAddr in preferences")
  end
  return make_lunchbox_req(ip_addr)
end

function emit_state(driver, device)
  log.debug('Emitting state')
  device:emit_event(capabilities.switch.switch.off())
  is_two = not is_two
  socket.spawn(function()
    make_request2(device)

  end)
end

local driver = Driver('https-fails', {
  discovery = disco,
  lifecycle_handlers = {
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
