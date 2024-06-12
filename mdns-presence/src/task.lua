local cosock = require "cosock"
-- local mdns = require "st.mdns"
local utils = require "st.utils"
local log = require "log"

local SERVICE_TYPE = "_rdlink._tcp"
local DOMAIN = "local"
local INFO_REGEX = "^([^%.]+)%."

local env_socket = _envlibrequire("socket")
local call_rpc_method = _envlibrequire("util.call_rpc_method")
local mdns_meta = {}

function mdns_meta:settimeout(timeout)
    if type(timeout) == "number" then
        self.timeout = timeout
    elseif timeout == nil then
        self.timeout = nil
    end
    return 1
end

function mdns_meta:receive()
    local response, err, _ = self.inner_sock:receive()
    if not response and err == "timeout" then
        log.debug("receive timedout, calling select")
        _, err = cosock.socket.select({self.inner_sock}, {}, self.timeout)
        if err then return nil, err end
        response, err = self.inner_sock:receive()
    end
    return response, err
end

function mdns_meta:resolve(host, service_type, domain)
    call_rpc_method("resolver.mdns_resolve", {host = host, service_type = service_type, domain = domain})
    return self:receive()
end
function mdns_meta:discover(service_type, domain)
    call_rpc_method("resolver.mdns_discover", {service_type = service_type, domain = domain})
    return self:receive()
end

local function new_mdns()
  local inner_sock, err = env_socket.mdns()
  if not inner_sock then return inner_sock, err end
  inner_sock:settimeout(0)
  inner_sock.setwaker = function(kind, waker)
    inner_sock._waker = waker
  end
  return setmetatable({inner_sock = inner_sock, class = "mdns"}, { __index = mdns_meta})
end



local function tick(state, tx, rx)
    local mdns = assert(new_mdns())
    mdns:settimeout(60)
    for name, dev in pairs(state.devices) do
        print("attempting to resolve", name)
        local ret, err = mdns:resolve(name, SERVICE_TYPE, DOMAIN)
        if err then
            log.warn("Error resolving", err)
            goto continue
        end
        if dev.last_seen == nil or os.difftime(os.time(), dev.last_seen) > state.away_trigger then
            dev.last_state = true
            tx:send({
                kind = "presence-change",
                id = dev.id,
                is_present = true,
            })
        end
        dev.last_seen = os.time()
        ::continue::
    end
    for _name, dev in pairs(state.devices) do
        if os.difftime(os.time(), dev.last_seen or 0) > state.away_trigger and dev.last_state then
            dev.last_state = false
            tx:send({
                kind = "presence-change",
                id = dev.id,
                is_present = false,
            })
        end
    end
end

local function tick_discovery(state, tx, rx)
    if not next(state.devices) then
        return log.warn("No devices, skipping mdns query")
    end
    local mdns = assert(new_mdns())
    mdns:settimeout(60)
    local res, err = mdns:discover(SERVICE_TYPE, DOMAIN)
    log.debug("ANSWERS")
    if not res then
        return log.warn("discovery err", err)
    end
    if #res.answers == 0 then
        print("  NONE")
    end
    
    for _, ans in ipairs(res.answers) do
        local bare_name = (ans.name or ""):match(INFO_REGEX)
        log.debug(string.format("answer name %q", bare_name))
        local dev
        if not bare_name then
            goto continue
        end
        dev = state.devices[bare_name]
        if dev then
            log.debug("found device ", bare_name)
            if dev.last_seen == nil or os.difftime(os.time(), dev.last_seen) > state.away_trigger then
                dev.last_state = true
                tx:send({
                    kind = "presence-change",
                    id = dev.id,
                    is_present = true,
                })
            end
            dev.last_seen = os.time()
        end
        ::continue::
        print(string.format("  answer: %q", ans.name))
    end
    for _name, dev in pairs(state.devices) do
        if os.difftime(os.time(), dev.last_seen or 0) > state.away_trigger and dev.last_state then
            dev.last_state = false
            tx:send({
                kind = "presence-change",
                id = dev.id,
                is_present = false,
            })
        end
    end
end

local function task(state, tx, rx)
    while true do
        local event, rxs, err
        if event then
            log.debug(utils.stringify_table(event, "Event", true))
            if event.kind == "new-device" then
                state.devices[event.name] = {
                    id = event.id,
                    last_seen = event.last_seen,
                }
            end
        elseif err and err ~= "timeout" then
            log.error("Error in select/receive:", err)
        end
        tick_discovery(state, tx, rx)
        log.debug("waiting for message from driver")
        rx:settimeout(state.timeout)
        event, err = rx:receive()
    end
end

local function spawn_presence_task(initial_state, tx, rx)
    log.trace("spawn_presence_task")
    cosock.spawn(function()
        task(initial_state, tx, rx)
    end)
end

return {
    spawn_presence_task = spawn_presence_task,
}
