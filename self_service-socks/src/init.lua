
local Driver = require 'st.driver'
local log = require 'log'
local utils = require 'st.utils'
local json = require 'dkjson'
local capabilities = require 'st.capabilities'
local cosock = require 'cosock'


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

local function disco(driver, opts, cont)
  print('starting disco', cont)
  local device_list = driver.device_api.get_device_list()
  if not next(device_list) and cont() then
    print('discovering a device')
    local device_info = {
        type = 'LAN',
        deviceNetworkId = string.format('%s', os.time()),
        label = 'self-service-socks',
        profileReference = 'self-service-socks.v1',
        vendorProvidedName = 'self-service-socks',
    }
    local device_info_json = json.encode(device_info)
    assert(driver.device_api.create_device(device_info_json))
  end
end

local function make_request()
  local server_sock = cosock.socket.tcp()
  local client_sock = cosock.socket.tcp()
  assert(server_sock:bind("0.0.0.0", 0))
  server_sock:listen(1)
  local ip, port = server_sock:getsockname()
  print(ip, port)
  cosock.spawn(function()
    local socks = {}
    local start = cosock.socket.gettime()
    local diff = 0
    while diff < 30 do
      local client = assert(server_sock:accept())
      table.insert(socks, client)
      diff = cosock.socket.gettime() - start
    end
    for _,sock in ipairs(socks) do
      sock:close()
    end
    local idx = math.random(1,#socks)
    socks[idx]:close()
  end, "server task")

  cosock.spawn(function()
    for i=1,10 do
      local sock = cosock.socket.tcp()
      cosock.spawn(function()
        local s,e = sock:connect(ip, port)
        if not s then
          print("error", i, e)
          return
        end
        print("connected", i)
        print(i, sock:receive())
      end, string.format("socket %s task", i))
    end
  end, "client task")
end


local function emit_state(driver, device)
  log.debug('Emitting state')
  device:emit_event(capabilities.switch.switch.off())
  make_request()
end

local function init(driver, device)
  emit_state(driver, device)
end

local driver = Driver('Self Service Sock', {
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
