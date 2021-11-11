local lsocket = require "socket"
local internals = require "cosock.socket.internals"

local m = {}

local recvmethods = {
  receive = "timeout",
}

local sendmethods = {
  send = "timeout",
}

setmetatable(m, {__call = function()
  local inner_sock, err = lsocket.driver_lifecycle()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  return setmetatable({inner_sock = inner_sock, class = "driver_lifecycle{}"}, { __index = m})
end})

local passthrough = internals.passthroughbuilder(recvmethods, sendmethods)

m.receive = passthrough("receive")

m.send = passthrough("send")

function m:settimeout(timeout)
  self.timeout = timeout
end

internals.setuprealsocketwaker(m)

return m
