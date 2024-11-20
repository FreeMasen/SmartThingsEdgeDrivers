local disco = require "src.discovery"
local ws = require "src.task"
local ryaml = require("ryaml")
local json = (function()
    local s, m = pcall(require, "st.json")
    if s then return m end
    return require "dkjson"
end)()

local cosock = require "cosock"

local cmd_tx, cmd_rx = cosock.channel.new()
local dev_tx, dev_rx = cosock.channel.new()
dev_rx:settimeout(60)

local function print_debug(value, indent)
    indent = indent or ""
    local ty = type(value)
    if ty == "string"
    or ty == "number"
    or ty == "nil" 
    or ty == "boolean" 
    then
        return print(string.format("%s%q", indent, value))
    end
    if ty == "function" then
        return print(string.format("%s%s", indent, value))
    end
    if ty == "table" then
        print(ryaml.encode(value))
    end
end

cosock.spawn(function()
    local disco_sock, msg, ip, port = disco.find_devices()
    print("disco", msg, ip, port)
    local info = json.decode(msg or "")
    ws.spawn_ws_task(cmd_rx, dev_tx, info.ip, info.port)
    cmd_tx:send(ws.generate_ws_get_devices())
    while true do
        local msg, err = dev_rx:receive()
        if err == "timeout" then
            cmd_tx:send(ws.generate_ws_get_devices())
            goto continue
        end
        print_debug(msg or string.format("err: %q", err))
        ::continue::
    end
end)

cosock.run()
