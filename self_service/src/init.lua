
local Driver = require 'st.driver'
local log = require 'log'
local utils = require 'st.utils'
local json = require 'dkjson'
local capabilities = require 'st.capabilities'
local cosock = require 'cosock'
local http = cosock.asyncify("socket.http")
local lux = require("luxure")

local server = lux.Server.new_with(cosock.socket.tcp(), { env = 'debug' })

local function find_hub_ip(driver)
  if driver.environment_info.hub_ipv4 then
      return driver.environment_info.hub_ipv4
  end
  local s = cosock:udp()
  -- The IP address here doesn't seem to matter so long as its
  -- isn't '*'
  s:setpeername('192.168.0.0', 0)
  local localip, _, _ = s:getsockname()
  return localip
end

server.get_ip = function(self)
  if self.ip == nil or self.ip == '0.0.0.0' then
    self.ip = find_hub_ip(driver)
  end
  return self.ip
end

local function disco(driver, opts, cont)
  print('starting disco', cont)
  local device_list = driver.device_api.get_device_list()
  if not next(device_list) and cont() then
    print('discovering a device')
    local device_info = {
        type = 'LAN',
        deviceNetworkId = string.format('%s', os.time()),
        label = 'self-service',
        profileReference = 'self-service.v1',
        vendorProvidedName = 'self-service',
    }
    local device_info_json = json.encode(device_info)
    assert(driver.device_api.create_device(device_info_json))
  end
end

local function make_request()
  log.info(cosock.socket.gettime(), 'requesting hello world')
  if not server.port then return log.debug("server not yet listening") end
  local body, code, headers, msg = assert(http.request(string.format("http://%s:%s", server:get_ip(), server.port)))
  log.info(cosock.socket.gettime(), 'response', code, body)
end

local function emit_state(driver, device)
  log.debug('Emitting state')
  device:emit_event(capabilities.switch.switch.off())
  make_request()
end

local function init(driver, device)
  emit_state(driver, device)
end

local driver = Driver('Self Service', {
  discovery = disco,
  lifecycle_handlers = {
    init = init,
    added = init,
  },
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

server:listen()

cosock.spawn(function()
  while true do
    server:tick(log.error)
  end
end, "server run loop")

server:get('/', function(req, res)
  local sent = 0
  for i = 1, 1024 * 1024 do
    res:send(string.rep("a", 1024))
    sent = sent + 1024
    if i % 10000 then
      print("sent:", sent)
    end
    cosock.socket.sleep(0.01)
  end
end)

driver:run()
