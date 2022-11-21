local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local cosock = require("cosock")
local log = require("log")
local lustre = require("lustre")
local json = require("st.json")

























local function generate_ws_command_msg(device_id, command)
   return {
      type = "ExecuteCommand",
      device_id = device_id,
      command = command,
   }
end

local function generate_ws_open(device_id)
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
   return {
      type = "GetDevices",
   }
end

local function generate_ws_get_device(device_id)
   return {
      type = "GetDevice",
      device_id = device_id,
   }
end

local function spawn_ws_task(
   cmd_rx,
   cmd_tx,
   ip,
   port)

   local ws = lustre.WebSocket.client(assert(cosock.socket.tcp()), "/event-stream", lustre.Config.default())
   cosock.spawn(function()
      print("connecting")
      assert(ws:connect(ip, port))
      print("connected")
      while true do
         print("selecting")
         local rcvrs, _, select_err = cosock.socket.select({ ws, cmd_rx })
         print("selected")
         if type(rcvrs) == "nil" then
            goto continue
         end
         local r = rcvrs
         if (r[1] == ws or r[2] == ws) then
            local msg, ws_err = ws:receive()
            if type(msg) == "nil" and ws_err and ws_err ~= "timeout" then
               cmd_tx:send({
                  type = "Error",
                  err = ws_err,
                  level = "Fatal",
               })
               log.error("Error in websocket task", ws_err)
               return
            end
            cmd_tx:send(json.decode((msg).data))
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
                  level = "Warning",
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
