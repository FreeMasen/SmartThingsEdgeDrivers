local capabilities = require 'st.capabilities'
local Driver = require 'st.driver'
local log = require 'log'

local discovery = require 'disco'
local utils = require 'st.utils'

local driverNameID = "honestadmin11679.driverName"
local driverName = capabilities[driverNameID]

-- These handlers are primarily to make the log traffic
-- as chatty as possible
local function device_added(driver, device)
    device:emit_event(driverName.driverName(driver.NAME))
    log.trace('Added ' .. device.id)
end

local function device_init(driver, device)
    local url = driver:get_url()
    if url then
        device:emit_event(driverName.currentUrl(url))
    end
    log.trace('Init\'d ' .. device.id)
end

local function device_removed(driver, device)
    log.trace('Removed ' .. device.id)
end

local function info_changed(driver, device, event, ...)
    log.trace('Info Changed ', device.id, event, ...)
end

local driver = Driver('Driver Name', {
    lifecycle_handlers = {
        init = device_init,
        added = device_added,
        deleted = device_removed,
        infoChanged = info_changed,
    },
    discovery = discovery.disco_handler,
})


driver:run()
