local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local pcall = _tl_compat and _tl_compat.pcall or pcall; local cosock = require("cosock")
local socket = cosock.socket
local json = require("st.json")



local function create_udp_socket()
   local s = socket.udp()
   assert(s)
   local listen_ip = "0.0.0.0"
   local listen_port = 0

   assert(s:setsockname(listen_ip, listen_port))
   s:settimeout(8)
   return s
end



local function create_query()
   return json.encode({
      target = "myq-proxy",
      source = "st-driver",
   })
end



local function send_query(s)
   if not s then
      s = create_udp_socket()
   end
   local multicast_ip = "239.255.255.250"
   local multicast_port = 1919
   local multicast_msg = create_query()
   assert(s:sendto(multicast_msg, multicast_ip, multicast_port))
end






local function wait_for_reply(s, stop_rx)
   local rxs, _, err = cosock.socket.select({ s, stop_rx })
   if type(rxs) == "nil" then
      return nil, err
   end
   local r = rxs
   if r[1] == s or r[2] == s then
      return s:receivefrom()
   end
   err = err or "timeout"
   if r[1] == stop_rx or r[2] == stop_rx then
      err = "stopped"
   end
   return nil, err
end





local function query_once(s, stop_rx)
   send_query(s)
   return wait_for_reply(s, stop_rx)
end






local function spawn_stop_task(should_continue)
   local tx, rx = cosock.channel.new()
   cosock.spawn(function()
      while should_continue() do
         cosock.socket.sleep(1)
         if tx.link.closed then
            break
         end
      end
      tx:send()
   end)
   return rx
end






local function default_continue()
   return true
end





local function discover_proxy_server(
   should_continue)

   should_continue = should_continue or default_continue
   local stop_rx = spawn_stop_task(should_continue)
   local s = create_udp_socket()
   while true do
      local msg, ip, _port = query_once(s)
      if msg then
         local success, t = pcall(json.decode, msg)
         if success and t.ip and t.port then
            stop_rx:close()
            return t
         end
      elseif ip ~= "timeout" then

         return nil, ip
      end
   end
   stop_rx:close()
   return nil, "was stopped"
end

return {
   query_once = query_once,
   discover_proxy_server = discover_proxy_server,
}
