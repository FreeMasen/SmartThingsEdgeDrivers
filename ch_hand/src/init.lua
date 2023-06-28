local Driver = require "st.driver"
local log = require "log"
local caps = require 'st.capabilities'
local discovery = require "disco"
local utils = require "st.utils"

local cosock = require "cosock"
local server = require "server"

local function device_added(driver, device)
    log.warn("device_added", device.label or device.id)
    device:emit_event(caps.switch.switch.off())
    device:emit_event(caps.valve.valve.closed())
end

local function info_changed(driver, device)
end

local d = Driver("ch_hand", {
    lifecycle_handlers = {
        init = device_added,
        added = device_added,
        infoChanged = info_changed,
    },
    discovery = discovery.disco_handler,
    })
server(d)
d:call_on_schedule(60, function()
    cosock.socket.sleep(5)
end, "call_on_schedule")
d:run()
