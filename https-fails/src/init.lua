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

local function _req(http, device)
  local ip_addr = device.preferences.ipAddr
  local endpoint = device.preferences.endpoint
  if not (type(ip_addr) == "string" and #ip_addr > 0) then
    return log.warn("No ipAddr in preferences")
  end
  if not (type(endpoint) == "string") then
    endpoint = ""
  end
  local s, response, status, headers, status_msg = 
   pcall(http.request, string.format("https://%s/%s", ip_addr, endpoint))
  if not s then
    return log.warn("Unsuccessful:", response)
  end
  if s and status == 200 then
    return log.info("Success!", response and #response or "nil resp")
  end
  log.debug(string.format("Status: %q - %q", status, status_msg))
  log.debug(utils.stringify_table(headers, "Headers", true))
  if type(response) == "string" and #response > 0 then
    print("Response: %q", response)
  end
end

local function make_request(device)
  log.trace("make_request")
  _req(socket.asyncify "socket.http", device)
end

local function make_request2(device)
  log.trace("make_request2")
  _req(socket.asyncify "ssl.https", device)
end
local function make_luncheon_request(url)
  local luncheon = require "luncheon"
  local net_url = require "net.url"
  local ssl = require "cosock.ssl"
  local sock = assert(socket.socket.tcp())
  local url_table = net_url.parse(url)
  assert(sock:connect(url_table.host, url_table.port))
  sock = assert(ssl.wrap(sock,
    { mode = "client", protocol = "any", verify = "none", options = "all" }))
  assert(sock:dohandshake())
  local req = assert(luncheon.Request.new("GET", url_table.path, sock))
  req:send()
  local res = assert(luncheon.Response.tcp_source(sock))
  local ret = assert(res:get_body())
  sock:close()
  return ret, res.status, res:get_headers(), res.status_msg
end
local function make_request3(device)
  log.trace("make_request3")
  _req({
    request = make_luncheon_request
  }, device)
end

local function do_request(device)
  local req = make_request
  local version = device.preferences.version or 1
  if version == 1 then
    req = make_request
  elseif version == 2 then
    req = make_request2
  else
    req = make_request3
  end
  
  socket.spawn(function()
    req(device)
  end)
end

local function emit_state(driver, device)
  log.debug("Emitting state")
  
  local ev
  if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME, "on") == "on" then
    ev = capabilities.switch.switch.off()
  else
    ev = capabilities.switch.switch.on()
  end
  device:emit_event(ev)
  do_request(device)
end
local to
local function maybe_spawn_timeout(driver, device)
  local timeout = device.preferences.timeout or 0
  if to then
    driver:cancel_timer(to)
  end
  if timeout > 0 then
    log.debug("Spawning scheduled ", timeout)
    to = driver:call_on_schedule(timeout, function()
      do_request(device)
    end, "timeout-request")
  end
end

local driver = Driver('https-fails', {
  discovery = disco,
  lifecycle_handlers = {
    init = function(dri, dev)
      maybe_spawn_timeout(dri, dev)
      emit_state(dri, dev)
    end,
    added = function(dri, dev)
      maybe_spawn_timeout(dri, dev)
      emit_state(dri, dev)
    end,
    infoChanged = maybe_spawn_timeout,
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
