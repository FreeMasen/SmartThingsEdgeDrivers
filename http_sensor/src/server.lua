local lux = require 'luxure'
local sse = require 'luxure.sse'
local cosock = require 'cosock'
local dkjson = require 'st.json'
local log = require "log"
local static = require 'static'
local discovery = require 'disco'

---Find the Hub's IP address if not populated in the
--- environment info
---@param driver Driver
---@return string|nil
local function find_hub_ip(driver)
  if driver.environment_info.hub_ipv4 then
    return driver.environment_info.hub_ipv4
  end
  local s = cosock.socket:udp()
  -- The IP address here doesn't seem to matter so long as its
  -- isn't '*'
  s:setpeername('192.168.0.0', 0)
  local localip, _, _ = s:getsockname()
  return localip
end

--- Setup a multicast UDP socket to listen for the string "whereareyou"
--- which will respond with the full url for the server.
local function setup_multicast_disocvery(server)
  local function gen_url(server)
    local server_ip = assert(server:get_ip())
    return string.format("http://%s:%s", server:get_ip(), server.port)
  end

  cosock.spawn(function()
    while true do
      local ip = '239.255.255.250'
      local port = 9887
      local sock = cosock.socket.udp()
      print("setting up socket")
      assert(sock:setoption('reuseaddr', true))
      assert(sock:setsockname(ip, port))
      assert(sock:setoption('ip-add-membership', {
        multiaddr = ip,
        interface = '0.0.0.0'
      }))
      assert(sock:setoption('ip-multicast-loop', false))
      assert(sock:sendto(gen_url(server), ip, port))
      sock:settimeout(60)
      while true do
        print("receiving from")
        local bytes, ip_or_err, rport = sock:receivefrom()
        print("recv:", bytes, ip_or_err, rport)
        if ip_or_err == "timeout" or bytes == "whereareyou" then
          print("sending broadcast")
          assert(sock:sendto(gen_url(server), ip, port))
        else
          print("Error in multicast listener: ", ip_or_err)
          break
        end
      end
    end
  end)
end

return function(driver)
  local server = lux.Server.new_with(assert(cosock.socket.tcp()), {
    env = 'debug'
  })
  --- Connect the server up to a new socket
  server:listen()
  --- spawn a lua coroutine that will accept incomming connections and router
  --- their http requests
  cosock.spawn(function()
    while true do
      server:tick(print)
    end
  end)

  --- Middleware to log all incoming requests with the method and path
  server:use(function(req, res, next)
    log.debug(string.format('%s %s', req.method, req.url.path))
    next(req, res)
  end)

  --- Middleware to redirect all 404s to /index.html
  server:use(function(req, res, next)
    if (not req.url.path) or req.url.path == "/" then
      req.url.path = "/index.html"
    end
    return next(req, res)
  end)

  --- Middleware for parsing json bodies
  server:use(function(req, res, next)
    local h = req:get_headers()
    if req.method ~= 'GET' and h:get_one("content-type") == 'application/json' then
      req.raw_body = req:get_body()
      assert(req.raw_body)
      local success, body = pcall(dkjson.decode, req.raw_body)
      if success then
        req.body = body
      else
        print('failed to parse json', body)
      end
    end
    next(req, res)
  end)

  --- The static routes
  server:get('/index.html', function(req, res)
    res:set_content_type('text/html')
    res:send(static:html())
  end)
  server:get('/index.js', function(req, res)
    res:set_content_type('text/javascript')
    res:send(static:js())
  end)
  server:get('/style.css', function(req, res)
    res:set_content_type('text/css')
    res:send(static:css())
  end)

  server:get("/device/:device_id", function(req, res)
    local dev = lux.Error.assert(driver:get_device_info(req.params.device_id))
    local state = lux.Error.assert(driver:get_sensor_state(dev))
    res:send(dkjson.encode(state))
  end)

  server:get('/info', function(req, res)
    local devices_list = driver:get_sensor_states()
    res:send(dkjson.encode(devices_list))
  end)

  --- Quiet the 60 second print statement about the server's address
  server:post('/quiet', function(req, res)
    if driver.ping_loop == nil then
      res:send('Not currently printing')
      return
    end
    driver:cancel_timer(driver.ping_loop)
    driver.ping_loop = nil
    res:send('Stopped ping loop')
  end)

  --- Create a new http button on this hub
  server:post('/newdevice', function(req, res)
    local device_name, device_id, err_msg = discovery.add_sensor_device(driver, nil,
      driver.bridge_id)
    if err_msg ~= nil then
      log.error('error creating new device ' .. err_msg)
      res:set_status(503):send('Failed to add new device ')
      return
    end
    res:send(dkjson.encode({
      device_id = device_id,
      device_name = device_name,
    }))
  end)

  server:put("/profile", function(req, res)
    if not req.body.device_id or not req.body.profile then
      res:set_status(400):send('bad request')
      return
    end

    local dev = lux.Error.assert(driver:get_device_info(req.body.device_id))
    lux.Error.assert(dev:try_update_metadata({
      profile = req.body.profile
    }))
    res:set_status(200):send("{}")
  end)

  --- Handle the state update for a device
  server:put('/device_state', function(req, res)
    if not req.body.device_id or not req.body.state then
      res:set_status(400):send('bad request')
      return
    end
    local device = driver:get_device_info(req.body.device_id)
    if not device then
      res:set_status(404):send('device not found')
      return
    end
    print("emitting state")
    driver:emit_state(device, req.body.state)
    print("replying with raw body")
    res:send(req.raw_body)
  end)

  server:get('/subscribe', function (req, res)
    local tx, rx = cosock.channel.new()
    table.insert(driver.sse_txs, tx)
    print("creating sse stream")
    local stream = sse.Sse.new(res, 4)
    print("starting sse loop")
    while true do
      print("waiting for sse event")
      local event, err = rx:receive()
      print("event recvd")
      if not event then
        print("error in sse, exiting", err)
        break
      end
      local data = dkjson.encode(event)
      print("sending", data)
      local _, err = stream:send(sse.Event.new():data(data))
      if err then
        print("error in sse, exiting", err)
        stream.tx:close()
        break
      end
    end
    rx:close()
  end)

  --- This route is for checking that the server is currently listening
  server:get('/health', function(req, res)
    res:send('1')
  end)

  --- Get the current IP address, if not yet populated
  --- this will look to either the environment or a short
  --- lived udp socket
  ---@param self lux.Server
  ---@return string|nil
  server.get_ip = function(self)
    if self.ip == nil or self.ip == '0.0.0.0' then
      self.ip = find_hub_ip(driver)
    end
    return self.ip
  end
  -- setup_multicast_disocvery(server)
  driver.server = server
end
