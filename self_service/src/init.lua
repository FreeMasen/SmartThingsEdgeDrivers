
local Driver = require 'st.driver'
local log = require 'log'
local json = require 'dkjson'
local capabilities = require 'st.capabilities'
local cosock = require 'cosock'

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

local function long_lived_sockets()
  local server = cosock.socket.tcp()
  server:bind("0.0.0.0", 0)
  server:listen()
  local params = {
    mode = "server",
    protocol = "any",
    certificate = "certs/cert.pem",
    key = "certs/key.pem",
    verify = {"none"},
    options = {"all", "no_sslv3"}
  }

  local ip, port = server:getsockname()
  cosock.spawn(function()
    while true do
      local client = assert(server:accept())
      local tls = assert(cosock.ssl.wrap(client, params))
      tls:dohandshake()
      while true do
        local bytes, err, partial = tls:receive()
        if not bytes then
          print(err, partial)
          break
        end
        local ct = tonumber(string.sub(bytes, 1, 1))
        print("C BYTES:", string.sub(bytes, 1, 1), #bytes)
        cosock.socket.sleep(ct / 2)
        tls:send(string.format("%s\n", bytes))
      end
    end
  end)
  local client = cosock.socket.tcp()
  client:connect(ip, port)
  print("wrapping client")
  local tls = assert(cosock.ssl.wrap(client, {
    mode = "client",
    protocol = "any",
    verify = {"none"},
    options = {"all", "no_sslv3"}
  }))
  print("wrapped client")
  tls:dohandshake()
  for i=1,10 do
    tls:send(string.format("%s\n", string.rep(tostring(i-1), 128 * i)))
    local bytes = assert(tls:receive())
    print("C BYTES:", string.sub(bytes, 1, 1), #bytes)
  end
end

local function emit_state(driver, device)
  log.debug('Emitting state')
  device:emit_event(capabilities.switch.switch.off())
  long_lived_sockets()
end

local function init(driver, device)
  -- emit_state(driver, device)
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

driver:run()
