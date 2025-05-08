local Driver = require 'st.driver'
local capabilities = require 'st.capabilities'
local discovery = require 'disco'

local createTargetId = "honestadmin11679.targetcreate"
local createTarget = capabilities[createTargetId];
local collectGarbageId = "honestadmin11679.collectgarbage"
local collectGarbage = capabilities[collectGarbageId];

local function is_bridge(device)
    return device:supports_capability_by_id(collectGarbageId)
end

local function emit_switch(driver, device, on)
    local ev
    if on then
        ev = capabilities.switch.switch.on()
    else
        ev = capabilities.switch.switch.off()
    end
    device:emit_event(ev)
end

local function device_init(driver, device)
    if not is_bridge(device) then
        emit_switch(driver, device, false)
    end
end

local driver = Driver(require("driver_name"), {
    lifecycle_handlers = {
        init = device_init,
        added = device_init,
    },
    discovery = discovery.disco_handler,
    capability_handlers = {
        [createTargetId] = {
            create = function(driver, device)
                discovery.add_sensor_device(driver, nil, driver.bridge_id)
            end
        },
        [collectGarbageId] = {
            collect = function(driver, device)
                collectgarbage("collect")
                collectgarbage("collect")
                memory.trim()
            end,
            create = function(driver, device)
                collectgarbage("collect")
                collectgarbage("collect")
                memory.trim()
            end,
        },
        [capabilities.switch.ID] = {
            [capabilities.switch.commands.on.NAME] = function(driver, device)
                emit_switch(driver, device, true)
            end,
            [capabilities.switch.commands.off.NAME] = function(driver, device)
                emit_switch(driver, device, false)
            end,
        },
    }
})


driver:run()
