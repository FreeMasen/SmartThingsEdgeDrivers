local Driver = require "st.driver"
local log = require "log"
local caps = require 'st.capabilities'
local discovery = require "disco"
local utils = require "st.utils"

local cosock = require "cosock"
local server = require "server"

local ctl_tx, ctl_rx = cosock.channel.new()
local lockup_running = false
local function try_lock_up(driver)
    if lockup_running then return end
    lockup_running = true
    local tx, rx = cosock.channel.new()
    local tx2, rx2 = cosock.channel.new()
    driver:register_channel_handler(rx, function(_, rx)
        log.debug("handling incoming message")
        log.debug("recieving rx")
        log.debug("received:", rx:receive())
        lockup_running = false
        log.debug("recieving ctl_rx")
        tx2:send({})
        ctl_rx:receive()
    end, "lockup")
    return tx, rx2
end


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
