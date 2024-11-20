

local record lustre
    record WebSocket
        record WebSocketMessage
            data: string
        end
        client: function(socket: any, path: string, config: Config): WebSocket
        connect: function(self:WebSocket, ip:string, port:integer): integer|nil, nil|string
        receive: function(self: WebSocket): WebSocketMessage|nil, nil|string
        send_text: function(self: WebSocket, msg: string): integer|nil, nil|string
    end
    record Config
        default: function(): Config
    end
end

return lustre
