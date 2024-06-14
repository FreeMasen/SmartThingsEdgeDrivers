local cosock = require "cosock"
local log = require "log"
local lustre = require "lustre"
local json = require "st.json"

local enum CommandMessageType
    "ExecuteCommand"
    "GetDevices"
    "GetDevice"
end

local record CommandMessage
    type: CommandMessageType
    device_id: string|nil
    command: string|nil
end
local enum DeviceMessageType
    "Error"
end
local enum ErrorLevel
    "Fatal"
    "Warning"
end
local record DeviceMessage
    type: DeviceMessageType
    err: string|nil
    level: ErrorLevel|nil
end

local function generate_ws_command_msg(device_id: string, command: string): CommandMessage
    return {
        type = "ExecuteCommand",
        device_id = device_id,
        command = command,
    }
end

local function generate_ws_open(device_id: string): CommandMessage
    return generate_ws_command_msg(device_id, "open")
end

local function generate_ws_close(device_id: string): CommandMessage
    return generate_ws_command_msg(device_id, "close")
end

local function generate_ws_on(device_id: string): CommandMessage
    return generate_ws_command_msg(device_id, "on")
end

local function generate_ws_off(device_id: string): CommandMessage
    return generate_ws_command_msg(device_id, "off")
end

local function generate_ws_get_devices(): CommandMessage
    return {
        type = "GetDevices",
    }
end

local function generate_ws_get_device(device_id: string): CommandMessage
    return {
        type = "GetDevice",
        device_id = device_id,
    }
end

local function spawn_ws_task(
    cmd_rx: cosock.channel.ReceiveHalf<CommandMessage>,
    cmd_tx: cosock.channel.SendHalf<DeviceMessage>,
    ip: string,
    port: integer
)
    local ws = lustre.WebSocket.client(assert(cosock.socket.tcp()), "/event-stream", lustre.Config.default())
    cosock.spawn(function()
        print("connecting")
        assert(ws:connect(ip, port))
        print("connected")
        while true do
            print("selecting")
            local rcvrs, _, select_err = cosock.socket.select({ws, cmd_rx})
            print("selected")
            if rcvrs is nil then
                goto continue
            end
            local r = rcvrs as {any}
            if (r[1] == ws or r[2] == ws) then
                local msg, ws_err = ws:receive()
                if msg is nil and ws_err and ws_err ~= "timeout" then
                    cmd_tx:send({
                        type = "Error",
                        err = ws_err,
                        level = "Fatal"
                    })
                    log.error("Error in websocket task", ws_err)
                    return
                end
                cmd_tx:send(json.decode((msg as lustre.WebSocket.WebSocketMessage).data))
            end
            if r[1] == cmd_rx or r[2] == cmd_rx then
                local msg, ch_err = cmd_rx:receive()
                print("cmd", msg, ch_err)
                if msg then
                    ws:send_text(json.encode(msg))
                else
                    cmd_tx:send({
                        type = "Error",
                        err = ch_err,
                        level = "Warning"
                    })
                end
            end
            if select_err ~= "timeout" then
                cmd_tx:send({
                    type = "Error",
                    err = select_err,
                    level = "Warning",
                })
            end
            ::continue::
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
