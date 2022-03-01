local api = require 'api'
local socket = require "socket"
local username = assert(os.getenv('UDM_USER'), 'No UDM_USER env variable')
local password = assert(os.getenv('PASSWORD'), 'No UDM_USER env variable')
local client = assert(os.getenv('UDM_TARGET'), 'No UDM_TARGET env variable')
local ip = os.getenv('UDM_IP') or '192.168.1.1'
local cookie, xsrf
cookie, xsrf = assert(api.login(ip, username, password))
while true do
  local is_present, err = api.check_for_presence(ip, client, cookie, xsrf)
  assert(type(is_present) == "boolean")
  assert(not err, string.format("%q", err))
  print(string.format("%s is %s", client, (is_present and "present") or "not present"))
  socket.sleep(5)
end
