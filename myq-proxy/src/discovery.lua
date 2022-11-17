local cosock = require "cosock"
local socket = cosock.socket
local json = (function()
    local s, m = pcall(require, "st.json")
    if s then return m end
    return require "dkjson"
end)()
local function find_devices(s)
  local multicast_ip = "239.255.255.250"
  local multicast_port = 1919
  if not s then
    s = socket.udp()
    assert(s)
    local listen_ip = "0.0.0.0"
    local listen_port = 0
  
  
    assert(s:setsockname(listen_ip, listen_port))
    s:settimeout(8)
  end
  local multicast_msg = json.encode({
    target = "myq-proxy",
    source = "st-driver",
  })
  assert(s:sendto(multicast_msg, multicast_ip, multicast_port))
  return s, s:receivefrom()
end

return {
  find_devices = find_devices,
}