local lux = require 'luxure'
local cosock = require 'cosock'
local dkjson = require 'st.json'
local caps = require 'st.capabilities'

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
        return string.format(
            "http://%s:%s",
            server:get_ip(),
            server.port
        )
    end
    
    cosock.spawn(function()
        while true do
            local ip = '239.255.255.250'
            local port = 9887
            local sock = cosock.socket.udp()
            print("setting up socket")
            assert(sock:setoption('reuseaddr', true))
            assert(sock:setsockname(ip, port))
            assert(sock:setoption('ip-add-membership', {multiaddr = ip, interface = '0.0.0.0'}))
            assert(sock:setoption('ip-multicast-loop', false))
            while true do
                sock:sendto(gen_url(server), ip, port)
                cosock.socket.sleep(10)
            end
        end
    end, "not-ssdp")
end

local function send_response(res, body, status)
    local status = status or 200
    res:add_header("content-type", "application/json")
    assert(res:set_status(status):send(body))
end
return function(driver, config)
    config = config or {}
    local server = lux.Server.new_with(cosock.socket.tcp(), {env = 'debug'})
    --- Connect the server up to a new socket
    server:listen()
    --- spawn a lua coroutine that will accept incomming connections and router
    --- their http requests
    driver:register_channel_handler(server.sock, function()
        server:tick(function(err)
            print("Error from tick: ", err)
        end)
    end, "server tick loop")

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

    --- Get a list of driver ids and driver names
    server:get('/info', function (req, res)
        local devices_list = {}
        for _, id in ipairs(driver.device_api.get_device_list()) do
            local device_info = driver:get_device_info(id)

            table.insert(devices_list, {
                device_id = id,
                device_name = device_info.label,
            })
        end

        send_response(res, dkjson.encode(devices_list))
    end)

    server:post('/switch', function(req, res)
        local device = driver:get_device_info(req.body.device_id)
        if not device then
            send_response(res, 'device not found', 404)
            return
        end
        local ev
        if device:get_latest_state("main", caps.switch.ID, caps.switch.switch.NAME, "on") == "on" then
            ev = caps.switch.switch.off()
        else
            ev = caps.switch.switch.on()
        end
        device:emit_event(ev)
        send_response(res, req.raw_body)
    end)
    server:post('/valve', function(req, res)
        local device = driver:get_device_info(req.body.device_id)
        if not device then
            send_response(res, 'device not found', 404)
            return
        end
        local ev
        if device:get_latest_state("main", caps.valve.ID, caps.valve.NAME, "open") == "open" then
            ev = caps.valve.valve.closed()
        else
            ev = caps.valve.valve.open()
        end
        device:emit_event(ev)
        send_response(res, req.raw_body)
    end)

    server:get("/thread-info", function(req, res)
        local resp
        if cosock.get_thread_metadata then
            local resp_t = {}
            local start = os.time()
            for th, info in pairs(cosock.get_thread_details()) do
                info.status = coroutine.status(th)
                info.age = os.difftime(start, info.last_wake)
                info.sock = tostring(res.socket)
                table.insert(resp_t, info)
            end
            resp = dkjson.encode(resp_t)
        else
            resp = dkjson.encode({
                error = string.format("cosock.get_thread_details was %s",
                    type(cosock.get_thread_details))
            })
        end
        
        send_response(res, resp)
    end)
    server:put("/toggle-verbose", function(req, res)
        local should_print = cosock.toggle_print()
        send_response(res, dkjson.encode({should_print = should_print}))
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
    setup_multicast_disocvery(server)
    -- setup_multicast_disocvery(server)
    driver.server = server
end
