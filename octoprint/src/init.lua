local cosock = require 'cosock'
local capabilities = require 'st.capabilities'
local Driver = require 'st.driver'
local log = require 'log'
local utils = require 'st.utils'

local discovery = cosock.asyncify 'disco'
local Octopi = cosock.asyncify 'octopi'
local DeviceState = cosock.asyncify 'device_state'

local HEATING = capabilities.thermostatOperatingState.thermostatOperatingState.heating()
local IDLE = capabilities.thermostatOperatingState.thermostatOperatingState.idle()
local ON = capabilities.switch.switch.on()
local OFF = capabilities.switch.switch.off()
local heatingSetpoint = capabilities.thermostatHeatingSetpoint.heatingSetpoint
local temperature = capabilities.temperatureMeasurement.temperature

local function update_state(device, state)
    log.trace('updating state')
    if state.switch.is_on == true then
        log.trace('emitting on')
        device:emit_event(ON)
    elseif state.switch.is_on == false then
        log.trace('emitting off')
        device:emit_event(OFF)
    end
    local bed = device.profile.components['bed']
    local tool = device.profile.components['tool']
    if state.bed.is_heating == true then
        log.trace('bed is heating')
        bed:emit_event(HEATING)
    elseif state.bed.is_heating == false then
        log.trace('bed isn\'t heating')
        bed:emit_event(IDLE)
    end
    if state.bed.actual ~= nil then
        log.trace('bed temp', state.bed.actual)
        bed:emit_event(temperature{
            value = state.bed.actual,
            unit = 'C',
        })
    end
    if state.bed.target ~= nil then
        log.trace('bed target', state.bed.target)
        bed:emit_event(
            heatingSetpoint{
                value = state.bed.target,
                unit = 'C',
            }
        )
    end
    if state.tool.is_heating == true then
        log.trace('tool is heating')
        tool:emit_event(HEATING)
    end
    if state.tool.is_heating == false then
        log.trace('tool isn\'t heating')
        tool:emit_event(IDLE)
    end
    if state.tool.actual ~= nil then
        log.trace('tool temp', state.tool.actual)
        tool:emit_event(temperature{
            value = state.tool.actual,
            unit = 'C',
        })
    end
    if state.tool.target ~= nil then
        log.trace('tool target', state.tool.target)
        tool:emit_event(
            heatingSetpoint{
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

--- Start the poll loop for a device
---@param driver Driver
---@param device Device
---@param octopi Octopi
local function start_poll(driver, device, octopi)
    local octopi = octopi or device:get_field('octopi')
    if not octopi then
        error('octopi is nil')
    end
    driver.device_poll_handles[device.id] = true
    local poll_name = string.format('%s-poll', device.label or device or 'none')
    log.debug('start poll for', poll_name)
    cosock.spawn(function()
        while driver.device_poll_handles[device.id] do
            check_state(device, octopi)
            cosock.socket.sleep(5)
        end
    end, poll_name)
end

--- Handle both the device_added and device_init lifecycle events
---@param driver Driver
---@param device Device
local function device_added(driver, device)
    log.debug('device_added')
    local api_key = device:get_field('api_key')
    local printer_url = device:get_field('printer_url')
    log.debug(utils.stringify_table({api_key =  api_key, printer_url = printer_url}, 'persistent', true))
    if not printer_url then
        log.debug('looking up device')
        for _, p in ipairs(discovery.ssdp_query()) do
            if device.device_network_id == p.id then
                printer_url = p.url
                device:set_field('printer_url', printer_url, {persist = true})
                break
            end
        end
    end
    log.debug(utils.stringify_table({api_key =  api_key, printer_url = printer_url}, 'persistent', true))
    
    local octopi = Octopi.new(
        device.id,
        device.name,
        printer_url,
        device.preferences.usnm,
        api_key
    )
    device:set_field('octopi', octopi)
    local s, e = assert(octopi:gain_authorization())
    log.debug("authorized?", s, e)
    if type(s) == 'string' then
        device:set_field('api_key', s, {persist = true})
        driver.datastore:save()
    else
        log.debug('bad api key from gain_authorization', e or utils.stringify_table(s, 'api_key', true))
    end

    start_poll(driver, device, octopi)
end

---Handle the device removed lifecycle event
---@param driver Driver
---@param device Device
local function device_removed(driver, device)
    driver.device_poll_handles[device.id] = nil
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
    log.debug(utils.stringify_table(device.preferences, 'preferences', true))
    if not octopi:has_key() then
        octopi.user = device.preferences.usnm
        local s = assert(octopi:gain_authorization())
        if type(s) == 'string' then
            local printer = driver.datastore.printers[device.device_network_id]
            printer.api_key = s
        end
        start_poll(driver, device, octopi)
    end
end

local driver = Driver('Octoprint', {
    lifecycle_handlers = {
        init = device_added,
        added = device_added,
        removed = device_removed,
        infoChanged = info_changed,
    },
    capability_handlers = {
        [capabilities.switch.ID] = {
            [capabilities.switch.commands.on.NAME] = function (_, device)
                log.warn('Cannot turn on printer')
                device:emit_event(OFF)
            end,
            [capabilities.switch.commands.off.NAME] = handle_off
        },
        [capabilities.thermostatHeatingSetpoint.ID] = {
            [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
        },
    },
    discovery = discovery.disco_handler,
})

driver.device_poll_handles = {}
driver:run()
