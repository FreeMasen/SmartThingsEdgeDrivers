local lux = require "luxure"
local sse = require "luxure.sse"
local cosock = require "cosock"
local json = require "st.json"
local log = require "log"
local static = require "static"
local discovery = require "disco"

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
  s:setpeername("192.168.0.0", 0)
  local localip, _, _ = s:getsockname()
  return localip
end

return function(driver)
  local server = lux.Server.new_with(cosock.socket.tcp(), {
    env = "debug",
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
    local start = cosock.socket.gettime()
    next(req, res)
    local diff = cosock.socket.gettime() - start
    local diff_s
    if diff > 0.5 then
      diff_s = string.format("%.03fs", diff)
    else
      diff_s = string.format("%.01fms", diff * 1000)
    end
    log.debug(string.format("Responded %s to request %s %s in %s", res.status, req.method,
                            req.url.path, diff_s))
  end)

  --- Middleware to redirect all 404s to /index.html
  server:use(function(req, res, next)
    next(req, res)
    if not req.handled and req.method == "GET" and req.url ~= "/favicon.ico" and res.status == 404 then
      res.headers:append("Location", "/index.html")
      res:set_status(301):send()
    end
  end)

  --- Middleware for parsing json bodies
  server:use(function(req, res, next)
    local h = req:get_headers()
    if req.method ~= "GET" and h:get_one("content-type") == "application/json" then
      req.raw_body = req:get_body()
      assert(req.raw_body)
      local success, body = pcall(json.decode, req.raw_body)
      if success then
        req.body = body
      else
        print("failed to parse json", body)
      end
    end
    next(req, res)
  end)

  --- The static routes
  server:get("/index.html", function(req, res)
    res:set_content_type("text/html")
    res:send(static:html())
  end)
  --- The static routes
  server:get("/", function(req, res)
    res:set_content_type("text/html")
    res:send(static:html())
  end)
  server:get("/index.js", function(req, res)
    res:set_content_type("text/javascript")
    res:send(static:js())
  end)
  server:get("/style.css", function(req, res)
    res:set_content_type("text/css")
    res:send(static:css())
  end)

  --- Get a list of driver ids and driver names
  server:get("/info", function(req, res)
    local devices_list = {}
    for _, device in ipairs(driver:get_devices()) do
      local switch_state = device:get_latest_state("main", "switch", "switch", "off")
      table.insert(devices_list, {
        device_id = device.id,
        device_name = device.label,
        state = {
          switch = switch_state,
        },
      })
    end

    res:send(json.encode(devices_list))
  end)

  --- Quiet the 60 second print statement about the server's address
  server:post("/quiet", function(req, res)
    if driver.ping_loop == nil then
      res:send("Not currently printing")
      return
    end
    driver:cancel_timer(driver.ping_loop)
    driver.ping_loop = nil
    res:send("Stopped ping loop")
  end)

  --- Create a new http button on this hub
  server:post("/newdevice", function(req, res)
    local device_name, device_id, err_msg = discovery.add_device(driver)
    if err_msg ~= nil then
      log.error("error creating new device " .. err_msg)
      res:set_status(503):send("Failed to add new device")
      return
    end
    res:send(json.encode({
      device_id = device_id,
      device_name = device_name,
    }))
  end)

  --- Handle the state update for a device
  server:put("/device_state", function(req, res)
    if not req.body.device_id or not req.body.state then
      res:set_status(400):send("bad request")
      return
    end
    local device = driver:get_device_info(req.body.device_id)
    if not device then
      res:set_status(404):send("device not found")
      return
    end
    print("emitting state")
    driver:emit_state(device, req.body.state.switch == "on")
    print("replying with raw body")
    res:set_content_type("application/json"):send(req.raw_body)
  end)

  ---Update a device's label
  server:post("/newlabel", function(req, res)
    if not req.body.device_id or not req.body.name then
      res:set_status(400):send("Failed to parse newlabel json")
      return
    end
    local device = driver:get_device_info(req.body.device_id)
    if not device then
      res:set_status(404):send("Failed to update device, unknown")
      return
    end
    local suc, err = device:try_update_metadata({
      vendor_provided_label = req.body.name,
    })
    if not suc then
      local msg = string.format("error sending device update %s", err)
      log.debug(msg)
      res:set_status(503):send(msg)
      return
    end
    res:set_content_type("application/json"):send(json.encode({
      label = req.body.name,
    }))
  end)

  --- This route is for checking that the server is currently listening
  server:get("/health", function(req, res)
    res:send("1")
  end)

  server:get("/datastore", function(req, res)
    local body = json.encode(driver.datastore:get_serializable())
    res:set_content_type("application/json"):send(body)
  end)

  server:put("/datastore/:key", function(req, res)
    if not req.body then
      return res:set_status(500):send(json.encode({
        error = "expected json body"
      }))
    end
    driver.datastore[req.params.key] = req.body
    res
      :set_status(200)
      :send("{}")
  end)

  server:delete("/datastore", function(req, res)
    local device_id = req.body and req.body.device_id
    driver:clear_log(device_id)
    res
      :set_status(200)
      :send("{}")
  end)

  server:get("/subscribe", function(req, res)
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
      local data = json.encode(event)
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

  --- Get the current IP address, if not yet populated
  --- this will look to either the environment or a short
  --- lived udp socket
  ---@param self lux.Server
  ---@return string|nil
  server.get_ip = function(self)
    if self.ip == nil or self.ip == "0.0.0.0" then
      self.ip = find_hub_ip(driver)
    end
    return self.ip
  end

  driver.server = server
end
