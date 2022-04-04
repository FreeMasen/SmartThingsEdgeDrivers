local cosock = require "cosock"
local log = require "log"
local api = cosock.asyncify "api"
local utils = require 'st.utils'

local function is_nil_or_empty_string(v)
  if type(v) == 'string' then
    return #v == 0
  end
  return true
end

local NEW_CLIENT = "new-client"
local CREDS_UPDATE = "credentials-update"

---Create a new client message table
---@param device_id string The device id for this client
---@param name string The target name provided by the preferences
---@param state boolean If the target is currently present
---@return table
local function new_client_message(device_id, name, state)
  return {
    type = NEW_CLIENT,
    device_id = device_id,
    name = name,
    state = state,
  }
end

local function creds_update_message(ip, username, password)
  return {
    type = CREDS_UPDATE,
    ip = ip,
    username = username,
    password = password,
  }
end

local function get_name_and_current_state(device_names, client)
  local device = device_names[client.name]
  if device then
    return client.name, device
  end
  device = device_names[client.hostname]
  if device then
    return client.hostname, device
  end
  device = device_names[client.mac]
  if device then
    return client.mac, device
  end
end

local function check_states(ip, device_names, creds, event_tx)
  log.trace("check_states")
  if not (creds.xsrf and creds.cookie) then
    local cookie, xsrf = api.login(ip, creds.username, creds.password)
    if not cookie then
      error(string.format("Error logging in %q", xsrf))
    end
    creds.cookie = cookie
    creds.xsrf = xsrf
  end
  local sites, err = api.get_sites(ip, creds.cookie, creds.xsrf)
  if not sites then
    error(string.format("Error getting sites %q", err))
  end
  --- A set of all client ids currently tracked indexed by client name
  local missing_clients = {}
  for key, dev in pairs(device_names) do
    missing_clients[key] = dev.id
  end
  for _, client in ipairs(sites.data) do
    local name, current_state = get_name_and_current_state(device_names, client)
    if not name then
      goto continue
    end
    missing_clients[name] = nil
    local now = cosock.socket.gettime()
    local diff = now - client.last_seen
    local next_state = diff < 60
    if current_state.state ~= next_state then
      log.debug("Sending device update ", current_state.id, next_state)
      event_tx:send({
        device_id = current_state.id,
        state = next_state
      })
      current_state.state = next_state
    end
    ::continue::
  end
  --- Set all missing devices to not present
  for device_name, device_id in pairs(missing_clients) do
    log.debug("missing name ", device_name,
    device_names[device_name] and utils.stringify_table(device_names[device_name]))
    if device_names[device_name].state then
      event_tx:send({
        device_id = device_id,
        state = false,
      })
      device_names[device_name].state = false
    end
  end
end

local function dump_device_names(device_names)
  print(utils.stringify_table(device_names))
end

local function spawn_presence_task(ip, device_names, username, password, timeout)
  log.trace("spawn_presence_task")
  dump_device_names(device_names)
  local update_tx, update_rx = cosock.channel.new()
  local event_tx, event_rx = cosock.channel.new()
  cosock.spawn(function()
    local creds = {
      cookie = nil,
      xsrf = nil,
      username = username,
      password = password,
      timeout = timeout or 5,
    }
    while true do
      log.debug("Waiting for message")
      local ready, msg, err
      ready, err = cosock.socket.select({update_rx}, {}, creds.timeout)
      if ready then
        msg, err = update_rx:receive()
      end
      if msg then
        log.debug("Got message", msg.type)
        if msg.type == NEW_CLIENT then
          device_names[msg.name] = {
            state = false,
            id = msg.device_id,
          }
          dump_device_names(device_names)
        elseif msg.type == CREDS_UPDATE then
          creds.username = msg.username or username
          creds.password = msg.password or password
          creds.cookie = nil
          creds.xsrf = nil
          creds.timeout = msg.timeout or 5
          ip = msg.ip or ip
        else
          log.warn("unknown message type", utils.stringify_table(msg, "msg", true))
        end
      else
        log.debug("No message", err)
      end
      if err and err ~= "timeout" then
        log.error(string.format("Error receiving from update_rx: %q", err))
        goto continue
      end
      if is_nil_or_empty_string(ip)
      or is_nil_or_empty_string(creds.username)
      or is_nil_or_empty_string(creds.password) then
        local missing
        if is_nil_or_empty_string(ip) then
          missing = "ip"
        end
        if is_nil_or_empty_string(creds.username) then
          if not missing then
            missing = "username"
          else
            missing = missing .. "/username"
          end
        end
        if is_nil_or_empty_string(creds.password) then
          if not missing then
            missing = "password"
          else
            missing = missing .. "/password"
          end
        end
        log.warn(string.format("No %q", missing))
        goto continue
      end
      local s, err = pcall(check_states, ip, device_names, creds, event_tx)
      if not s then
        log.error("Failed in presence pass", err)
      else
        log.debug("Successfully checked sites")
      end
      ::continue::
    end
  end, "presence-task")
  return update_tx, event_rx
end

return {
  spawn_presence_task = spawn_presence_task,
  new_client_message = new_client_message,
  creds_update_message = creds_update_message,
}
