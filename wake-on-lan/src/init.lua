local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local wakeonlan = require "wakeonlan"

local function info_changed(driver, device, event)
    log.trace("wake-on-lan: info changed ", device.id, event)
end

local function push(driver, device, command)
    log.debug("[" .. device.device_network_id .. "] calling push")
    local mac = device.preferences.macAddress or device.preferences.macAddr
    local sop = device.preferences.secureon
    local port = device.preferences.port
    assert(wakeonlan.send_magic_packet(mac, sop, port))
end

local driver = Driver("wake-on-lan", {
    discovery = wakeonlan.discovery_handler,
    lifecycle_handlers = {
        infoChanged = info_changed,
    },
    capability_handlers = {
        [capabilities.momentary.ID] = {
            [capabilities.momentary.commands.push.NAME] = push,
        },
    },
})

log.trace("Starting " .. driver.NAME)
driver:run()
log.info("Exiting " .. driver.NAME)
