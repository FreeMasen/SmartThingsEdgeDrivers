local cosock = require "cosock"
local socket = cosock.socket
local json = require "st.json"

--- Create the UDP socket used in our not-ssdp discovery protocol
--- @return cosock.socket.udp
local function create_udp_socket(): cosock.socket.udp.UdpSocket
  local s = socket.udp()
  assert(s)
  local listen_ip = "0.0.0.0"
  local listen_port = 0

  assert(s:setsockname(listen_ip, listen_port))
  s:settimeout(8)
  return s
end

--- Generate the query string for our not-ssdp discovery protocol
--- @return string
local function create_query(): string
  return json.encode({
    target = "myq-proxy",
    source = "st-driver",
  })
end

--- Send the not-ssdp query to our multicast group
--- @param s {cosock.socket.udp} The socket to send on (default will be created if `nil`)
local function send_query(s: cosock.socket.udp.UdpSocket)
  if not s then
    s = create_udp_socket()
  end
  local multicast_ip = "239.255.255.250"
  local multicast_port = 1919
  local multicast_msg = create_query()
  assert(s:sendto(multicast_msg, multicast_ip, multicast_port))
end

--- Wait for the not-ssdp reply or a cancel signal from the rx 
--- 
--- Returns `string, string, integer` on success otherwise returns `nil, string`
--- @param s {cosock.socket.udp}
--- @return string|nil, string, integer|nil
local function wait_for_reply(s: cosock.socket.udp.UdpSocket, stop_rx: cosock.channel.ReceiveHalf<nil>): string|nil, string, integer|nil
  local rxs, _, err = cosock.socket.select({s, stop_rx})
  if rxs is nil then
    return nil, err
  end
  local r = rxs as {any}
  if r[1] == s or r[2] == s then
    return s:receivefrom()
  end
  err = err or "timeout"
  if r[1] == stop_rx or r[2] == stop_rx then
    err = "stopped"
  end
  return nil, err
end

--- Send and recieve a query one time
--- @param s {cosock.socket.udp} UDP socket to query
--- @param stop_rx {cosock.channel} Channel to listen for cancel signals on
--- @return string|nil, string, integer|nil
local function query_once(s: cosock.socket.udp.UdpSocket,stop_rx: cosock.channel.ReceiveHalf<nil>): string|nil, string, integer|nil
  send_query(s)
  return wait_for_reply(s, stop_rx)
end

--- Spawn a cosock task that probes the provided callback and sleeps for 1 second
--- in a loop until the provided callback returns `false` at which point it will send
--- `nil` on the tx paired with the returned rx
--- @param should_continue {fn():bool} The callback to probe
--- @return {cosock.channel}
local function spawn_stop_task(should_continue: function():boolean): cosock.channel.ReceiveHalf<nil>
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

local record QueryResponse
  ip: string
  port: integer
end

local function default_continue(): boolean
  return true
end

--- Attempt to discover the proxy server on the local network. This function will either yield
--- until an expected reply is received or until a provided callback returns `false`
--- @param should_continue {fun():bool}
--- @return {ip: string, port: integer}|nil, nil|string
local function discover_proxy_server(
    should_continue: function(): boolean | nil
  ): QueryResponse|nil, nil|string
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
      -- ip is an error message here and port is probably nil
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
