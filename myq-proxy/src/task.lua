local cosock = require "cosock"
local log = require "log"
local lustre = require "lustre"

local json = (function()
    local s, m = pcall(require, "st.json")
    if s then return m end
    return require "dkjson"
end)()

local function generate_ws_command_msg(device_id, command)
    return json.encode({
        type = "ExecuteCommand",
        device_id = device_id,
        command = command,
    })
end

local function generate_open(device_id)
    return generate_ws_command_msg(device_id, "open")
end

local function generate_ws_close(device_id)
    return generate_ws_command_msg(device_id, "close")
end

local function generate_ws_on(device_id)
    return generate_ws_command_msg(device_id, "on")
end

local function generate_ws_off(device_id)
    return generate_ws_command_msg(device_id, "off")
end

local function generate_ws_get_devices()
    return json.encode({
        type = "GetDevices",
    })
end

local function generate_ws_get_device(device_id)
    return json.encode({
        type = "GetDevice",
        device_id = device_id,
    })
end

local function generate_ws_get_devices()
    return json.encode({
        type = "GetDevices",
    })
end

local function spawn_ws_task(cmd_rx, cmd_tx, ip, port)
    local ws = lustre.WebSocket.client(assert(cosock.socket.tcp()), "/event-stream", lustre.Config.default())
    cosock.spawn(function()
        print("connecting")
        assert(ws:connect(ip, port))
        print("connected")
        while true do
            print("selecting")
            local rcvrs, _, err = cosock.socket.select({ws, cmd_rx})
            print("selected")
            if rcvrs[1] == ws or rcvrs[2] == ws then
                local msg, err = ws:receive()
                if err and err ~= "timeout" then
                    cmd_tx:send({
                        type = "Error",
                        err = err,
                        level = "Fatal"
                    })
                    return log.error("Error in websocket task", err)
                end
                cmd_tx:send(json.decode(msg.data))
            end
            if rcvrs[1] == cmd_rx or rcvrs[2] == cmd_rx then
                local msg, err = cmd_rx:receive()
                print("cmd", msg, err)
                ws:send_text(msg)
            end
        end
    end)
end

return {
    generate_ws_close = generate_ws_close,
    generate_ws_open = generate_ws_open,
    generate_ws_on = generate_ws_on,
    generate_ws_off = generate_ws_off,
    generate_ws_get_devices = generate_ws_get_devices,
    generate_ws_get_device = generate_ws_get_device,
    spawn_ws_task = spawn_ws_task,
}
