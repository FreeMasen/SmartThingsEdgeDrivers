local lux = require 'luxure'
local cosock = require 'cosock'
local dkjson = require 'st.json'
local log = require "log"
local static = require 'static'
local metrics_report = require "metrics_report"

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

return function(driver)
    local server = lux.Server.new_with(cosock.socket.tcp(), {env = 'debug'})
    --- Connect the server up to a new socket
    server:listen()
    --- spawn a lua coroutine that will accept incomming connections and router
    --- their http requests
    cosock.spawn(function()
        while true do
            server:tick(print)
        end
    end)

    cosock.spawn(function()
        while true do
            print(server:get_ip(), server.port)
            cosock.socket.sleep(5)
        end
    end)
    
    --- Middleware to log all incoming requests with the method and path
    server:use(function(req, res, next)
        local start = cosock.socket.gettime()
        next(req, res)
        local diff = cosock.socket.gettime() - start
        local diff_s
        if diff > 0.5 then
            diff_s = string.format('%.03fs', diff)
        else
            diff_s = string.format("%.01fms", diff * 1000)
        end
        log.debug(string.format('Responded %s to request %s %s in %s', res.status, req.method, req.url.path, diff_s))
    end)
    
    --- Middleware to redirect all 404s to /index.html
    server:use(function(req, res, next)
        next(req, res)
        if not req.handled
        and req.method == 'GET'
        and req.url ~= '/favicon.ico'
        then
            res.headers:append('Location', '/index.html')
            res:set_status(301):send()
        end
    end)
    
    --- Middleware for parsing json bodies
    server:use(function (req, res, next)
        local h = req:get_headers()
        if req.method == 'POST' and h:get_one("content-type") == 'application/json' then
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
    
    --- Get a list of driver ids and driver names
    server:get('/info', function (req, res)
        local report = metrics_report.generate_report()
        
        res:set_content_type("application/json")
        res:send(dkjson.encode(report))
    end)
    
    --- Handle the `push` and `held` events for a button
    server:post('/create_devices', function(req, res)
        local profile_id = req.body.profile_id
        local device_count = tonumber(req.body.device_count)
        local label = req.body.label or profile_id
        if not profile_id then
            res:set_status(400):send("no profile id provided")
            return
        end
        if not device_count then
            res:set_status(400):send("no device count provided")
            return
        end
        cosock.spawn(function()
            for i = 1, device_count do
                driver:add_device(profile_id, label)
                cosock.socket.sleep(1)
            end
        end)
        res:send("")
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
    driver.server = server
end
