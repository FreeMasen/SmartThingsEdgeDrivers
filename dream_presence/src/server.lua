local lux = require 'luxure'
local cosock = require 'cosock'
local dkjson = require 'dkjson'
local log = require "log"
local disco = require 'disco'
local utils = require 'st.utils'
cosock = cosock.socket


---Find the Hub's IP address if not populated in the
--- environment info
---@param driver Driver
---@return string|nil
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

return function(driver)
    local server = lux.Server.new_with(cosock.tcp(), {})
    --- Connect the server up to a new socket
    server:listen()

    --- Register the channel handler to respond to each incoming connection
    driver:register_channel_handler(server.sock, function ()
        server:tick()
    end)

    --- Middleware to log all incoming requests with the method and path
    server:use(function(req, res, next)
        local start = cosock.gettime()
        next(req, res)
        local diff = cosock.gettime() - start
        local diff_s
        if diff > 0.1 then
            diff_s = string.format('%.03fs', diff)
        else
            diff_s = string.format("%.01fms", diff * 1000)
        end
        log.debug(string.format('Responded to request %s %s in %s', req.method, req.url.path, diff_s))
    end)

    -- Middleware to redirect all 404s to /info
    server:use(function(req, res, next)
        next(req, res)
        if not req.handled
        and req.method == 'GET'
        and req.url ~= '/favicon.ico'
        then
            res.headers:append('Location', '/info')
            res:status(301):send()
        end
    end)

    --- Middleware for parsing json bodies
    server:use(function (req, res, next)
        local h = req:get_headers()
        if req.method == 'POST' and h.content_type == 'application/json' then
            req.raw_body = req:get_body()
            assert(req.raw_body)
            local success, body = pcall(dkjson.decode, req.raw_body)
            if success then
                req.body = body
            else
                print('failed to parse json')
            end
        end
        next(req, res)
    end)

    --- Get a list of driver ids and driver names
    server:get('/info', function (req, res)
        local devices_list = {}
        for _, id in ipairs(driver.device_api.get_device_list()) do
            local device_info = driver:get_device_info(id)
            table.insert(devices_list, {
                device_id = id,
                device_name = device_info.label,
                username = device_info.preferences.username,
                ip = device_info.preferences.udmIp,
                client_name = device_info.preferences.clientName
            })
        end

        res:content_type('application/json'):send(dkjson.encode(devices_list))
    end)

    --- Get a list of driver ids and driver names
    server:get('/discovery', function (req, res)
        --TODO, send unpnp xml reply
        local xml = string.format([[<?xml version="1.0">
        <root xmlns="urn:schemas-unp-org:device-1-0>"
        <specVersion>
          <major>2</major>
          <minor>0</minor>
        </specVersion>
        <device>
          <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
          <friendlyName>dream presence smartthings driver</friendlyName>
          <manufacturer>Robert Masen</manufacturer>
          <manufacturerURL>http://freemasen.com</manufacturerURL>
          <modelName>Dream Presence Driver</modelName>
          <UDN>uuid:%s</UDN>
          <serviceList></serviceList>
          <presentationURL>http://%s:%s/info</presentationURL>
        </device>
        </root>
        ]], server.uuid, server:get_ip(), server.port)
        res:content_type('application/xml'):send(xml)
    end)

    --- Create a new http button on this hub
    server:post('/newdevice', function(req, res)
      local success, device_id = pcall(disco.add_device, driver)
      log.debug('newdevice', success, device_id)
      if not success then
          log.error('error creating new device ' .. device_id)
          res:status(503):send('Failed to add new device')
          return
      end
      res:send(dkjson.encode({
          device_id = device_id,
      }))
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

    driver:call_on_schedule(5, function(driver)
      local ip = server:get_ip()
      if ip == nil or server.port == nil then
        return
      end
      log.debug(string.format('http://%s:%s', ip, server.port))
    end)
    driver.server = server
end
