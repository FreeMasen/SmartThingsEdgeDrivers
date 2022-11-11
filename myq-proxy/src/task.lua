local log = require "log"
local lustre = require "lustre"

return function(ip, port)
    local ws = lustre.Websocket.client(assert(cosock.socket.tcp()), "/event-stream", lustre.Config.default())
    cosock.spawn(function()
        assert(ws:connect())
        while true do
            local msg, err = ws:receive()
            if err and err ~= "timeout" then
                return log.error("Error in websocket task", err)
            end
            print(err or msg.type, (msg or {}).data)
        end
    end)
end
