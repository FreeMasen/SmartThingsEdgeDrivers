local cosock = require "cosock"
local mdns = require "st.mdns"
local utils = require "st.utils"
local log = require "log"

local SERVICE_TYPE = "_rdlink._tcp"
local DOMAIN = "local"
local INFO_REGEX = "([^%.]+).%_device%-info%.local"

local function tick(state, tx, rx)
    local res, err = mdns.discover(SERVICE_TYPE, DOMAIN)
    -- log.debug("ANSWERS")
    if not res then
        return log.warn("discovery err", err)
    end
    if #res.answers == 0 then
        -- print("  NONE")
    end
    
    for _, ans in ipairs(res.answers) do
        local bare_name = (ans.name or ""):match(INFO_REGEX)
        local dev
        if not bare_name then
            goto continue
        end
        dev = state.devices[bare_name]
        if dev then
            if dev.last_seen == nil or os.difftime(os.time(), dev.last_seen) > state.away_trigger then
                tx:send({
                    kind = "presence-change",
                    id = dev.id,
                    is_present = true,
                })
            end
            state.devices[bare_name] = os.time()
        end
        ::continue::
        -- print(string.format("  answer: %q", ans.name))
    end
    for _name, dev in pairs(state.devices) do
        if os.difftime(os.time(), dev.last_seen) > state.away_trigger then
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
        tick(state, tx, rx)
        rxs, err = cosock.socket.select({rx}, {}, state.timeout)
        if type(rxs) == "table" and #rxs > 0 then
            event, err = rxs[1]:receive()
        end
    end
end

local function spawn_presence_task(initial_state, tx, rx)
    cosock.spawn(function()
        task(initial_state, tx, rx)
    end)
end

return {
    spawn_presence_task = spawn_presence_task,
}
