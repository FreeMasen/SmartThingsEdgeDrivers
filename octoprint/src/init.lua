local cosock = require 'cosock'
local capabilities = require 'st.capabilities'
local Driver = require 'st.driver'
local log = require 'log'
local utils = require 'st.utils'

local discovery = cosock.asyncify 'disco'
local Octopi = cosock.asyncify 'octopi'
local DeviceState = cosock.asyncify 'device_state'

local function update_state(device, state)
    if state.switch.is_on == true then
        device:emit_event(capabilities.switch.switch.on())
    elseif state.switch.is_on == false then
        device:emit_event(capabilities.switch.switch.off())
    end
    local bed = device.profile.components['bed']
    if state.bed.is_heating == true then
        bed:emit_event(
            capabilities.thermostatOperatingState.thermostatOperatingState.heating()
        )
    elseif state.bed.is_heating == false then
        bed:emit_event(
            capabilities.thermostatOperatingState.thermostatOperatingState.idle()
        )
    end
    if state.bed.actual ~= nil then
        bed:emit_event(capabilities.temperatureMeasurement.temperature{
            value = state.bed.actual,
            unit = 'C',
        })
    end
    if state.bed.target ~= nil then
        bed:emit_event(
            capabilities.thermostatHeatingSetpoint.heatingSetpoint{
                value = state.bed.target,
                unit = 'C',
            }
        )
    end
    if state.tool.is_heating == true then
        device:emit_event(
            capabilities.thermostatOperatingState.thermostatOperatingState.heating()
        )
    end
    if state.tool.is_heating == false then
        device:emit_event(
            capabilities.thermostatOperatingState.thermostatOperatingState.idle()
        )
    end
    if state.tool.actual ~= nil then
        device:emit_event(capabilities.temperatureMeasurement.temperature{
            value = state.tool.actual,
            unit = 'C',
        })
    end
    if state.tool.target ~= nil then
        device:emit_event(
            capabilities.thermostatHeatingSetpoint.heatingSetpoint{
                value = state.tool.target,
                unit = 'C',
            }
        )
    end
end

--- Check the bed and extruder state along with the switch state
---@param device Device
---@param octopi Octopi
local function check_state(device, octopi)
    if not octopi then
        error('Octopi is nil')
    end
    local state = DeviceState.fetch(octopi, device)
    update_state(device, state)
end

--- Recursive poll for a single device
local function poll(driver, device, octopi)
    check_state(device, octopi)
    driver.device_poll_handles[device.id] = driver:call_with_delay(5, function ()
        poll(driver, device, octopi)
    end, string.format('%s poll', device.NAME))
end

--- Start the poll loop for a device
---@param driver Driver
---@param device Device
---@param octopi Octopi
local function start_poll(driver, device, octopi)
    local octopi = octopi or device:get_field('octopi')
    if not octopi then
        error('octopi is nil')
    end
    driver.device_poll_handles = driver.device_poll_handles or {}
    if driver.device_poll_handles[device.id] then
        driver:cancel_timer(driver.device_poll_handles[device.id])
    end
    poll(driver, device, octopi)
end

--- Handle both the device_added and device_init lifecycle events
---@param driver Driver
---@param device Device
local function device_added(driver, device)
    log.debug('device_added', device.NAME)

    if not driver.datastore.printers[device.device_network_id] then
        log.debug('looking up device')
        for _, printer in ipairs(discovery.ssdp_query()) do
            if not driver.datastore.printers[printer.id] then
                driver.datastore.printers[printer.id] = printer
            end
        end
    end
    local printer = driver.datastore.printers[device.device_network_id]
    local octopi = Octopi.new(
        device.id,
        device.name,
        printer.url,
        device.preferences.username,
        printer.api_key
    )
    device:set_field('octopi', octopi)
    local s = assert(octopi:gain_authorization())
    if type(s) == 'string' then
        printer.api_key = s
    end

    start_poll(driver, device, octopi)
end

---Handle the device removed lifecycle event
---@param driver Driver
---@param device Device
local function device_removed(driver, device)
    driver.device_poll_handles = driver.device_poll_handles or {}
    driver:cancel_timer(driver.device_poll_handles[device.id])
end

---Handle the off switch capability event
---@param driver Driver
---@param device Device
local function handle_off(driver, device)
    log.trace('handle_off')
    ---@type Octopi
    local octopi = device:get_field('octopi')
    if not octopi then
        log.error('failed to get octopi from device')
        return
    end
    local success, err = octopi:cancel_job()
    if not success then
        log.error('Failed to cancel current job', err)
        return
    end
    device:emit_event(capabilities.switch.switch.off())
end

---Handle the set_heating_setpoint capability event
---@param driver Driver
---@param device Device
---@param event table
local function set_heating_setpoint(driver, device, event)
    log.trace('set_heating_setpoint')
    local octopi = device:get_field('octopi')
    if not octopi then
        log.error('failed to get octopi from device')
        return
    end
    local new_temp = event.positional_args[1] or 0
    local s, err
    if event.component == 'bed' then
        s, err = octopi:adjust_bed_temp(new_temp)
    else
        s, err = octopi:adjust_tool_temp(new_temp)
    end
    if not s then
        log.error('Error adjusting temp for ', event.component, err)
    end
end

---Handle the info changed event, most likely this will be because of
---an update to the device preferences
---@param driver Driver
---@param device Device
local function info_changed(driver, device)
    local octopi = device:get_field('octopi')
    if not octopi then
        return log.error('Failed to get octopi from device')
    end
    if not octopi:has_key() then
        octopi.user = device.preferences.username
        local s = assert(octopi:gain_authorization())
        if type(s) == 'string' then
            local printer = driver.datastore.printers[device.device_network_id]
            printer.api_key = s
        end
        start_poll(driver, device)
    end
end

local driver = Driver('octopi', {
    lifecycle_handlers = {
        init = device_added,
        added = device_added,
        removed = device_removed,
        infoChanged = info_changed,
    },
    capability_handlers = {
        [capabilities.switch.ID] = {
            [capabilities.switch.commands.on.NAME] = function ()
                log.warn('Cannot turn on printer')
            end,
            [capabilities.switch.commands.off.NAME] = handle_off
        },
        [capabilities.thermostatHeatingSetpoint.ID] = {
            [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
        },
    },
    discovery = discovery.disco_handler,
})
---This will keep a map of raw device data persistent. This will
---Include the device network id, url and api_key when granted
driver.datastore.printers = driver.datastore.printers or {}
driver:run()
