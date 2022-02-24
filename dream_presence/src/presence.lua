local cosock = require "cosock"
local log = require "log"
local api = require "api"
local utils = require 'st.utils'

local function is_nil_or_empty_string(v)
  if type(v) == 'string' then
    return #v == 0
  end
  return true
end

local function spawn_presence_task(ip, device_names, username, password)
  local update_tx, update_rx = cosock.channel.new()
  local event_tx, event_rx = cosock.channel.new()
  cosock.spawn(function()
    local cookie, xsrf
    update_rx:settimeout(5)
    while true do
      local msg, err = update_rx:receive()
      if msg then
        if msg.type == "new-client"
        and device_names[msg.name] == nil then
          device_names[msg.name] = {
            state = false,
            id = msg.device_id,
          }
        elseif msg.type == "credentials-update" then
          username = msg.username or username
          password = msg.password or password
          ip = msg.ip or ip
        else
          log.warn("unknown message type", utils.stringify_table(msg, "msg", true))
        end
      end
      if is_nil_or_empty_string(ip)
      or is_nil_or_empty_string(username)
      or is_nil_or_empty_string(password) then
        goto continue
      end
      local s, err = pcall(function()
        if not (xsrf and cookie) then
          cookie, xsrf = assert(api.login(ip, username, password))
        end
        local sites = assert(api.get_sites(ip, cookie, xsrf))

        for _, client in ipairs(sites.data) do
          local current_state = device_names[client.name] ~= nil
          or device_names[client.hostname]
          or device_names[client.mac]
          if current_state then
            local now = cosock.socket.gettime()
            local diff = now - client.last_seen
            local next_state = diff < 60
            if current_state ~= next_state then
              event_tx.send({
                device_id = current_state.device_id,
                state = next_state
              })
              current_state.state = next_state
            end
          end
        end
        return 1
      end)
      if not s then
        log.error("Failed in presence pass", err)
      end
      ::continue::
    end
  end, "presence-task")
  return update_tx, event_rx
end

return {
  spawn_presence_task = spawn_presence_task,
}
