local log = require 'log'
local utils = require 'st.utils'
local capabilities = require 'st.capabilities'
local HEATING = capabilities.thermostatOperatingState.thermostatOperatingState.heating()

---@class SwitchState
---@field public is_on boolean?
local SwitchState = {}

function SwitchState.all()
    return {
        is_on = false,
    }
end

---@class TempState
---@field public target number?
---@field public actual number?
---@field public is_heating boolean?
local TempState = {}

function TempState.all()
    return {
        actual = 0,
        target = 0,
        is_heating = false
    }
end

---@class DeviceState
---@field public switch SwitchState?
---@field public bed TempState?
---@field public tool TempState?
local DeviceState = {}
DeviceState.__index = DeviceState

---Helper for probing a deeply nested object that might be null at any point
--- ```lua
--- assert(get_with_early_return({a = { b = { c = { d = 1}}}}, 'a', 'b', 'c', 'd') == 1)
--- assert(get_with_early_return({a = { b = { }}}}, 'a', 'b', 'c', 'd') == nil)
--- ```
---@param t table The table to probe
---@vararg string The list of keys as strings
---@return any|nil
local function get_with_early_return(t, ...)
    if type(t) ~= 'table' then
        return nil
    end
    local v = t
    for _, key in ipairs({...}) do
        local v2 = v[key]
        if v2 == nil then
            return nil
        end
        v = v2
    end
    return v
end

--- Check if the printer is actively working on a job
--- which drives the switch state for this device
---@param octopi Octopi The octopi instance for this device
---@param device Device the Device model for this device
local function check_switch_state(octopi, device)
    log.trace('check_switch_state', octopi.id)
    local ret = {}
    local remote_state_str, err = octopi:check_state()
    if not remote_state_str then
        log.error('Failed to check switch state', err)
        return SwitchState.all()
    end
    local current_state = get_with_early_return(
        device,
        'state_cache',
        'main',
        'switch',
        'switch',
        'value'
    )
    if current_state == nil then
        ret.is_on = remote_state_str == 'Printing'
    end
    if remote_state_str ~= 'Printing' and current_state == 'on' then
        ret.is_on = false
    end
    if remote_state_str == 'Printing' and current_state == 'off' then
        ret.is_on = true
    end
    return ret
end

---Compare the provided temperature `info` to the state_cache, returning
---the elements that have changed
---@param device Device The device to check against
---@param component string The string name of the component (bed or main)
---@param info TemperatureInfo The info to check against
---@return TempState
local function compare_temp_states(device, component, info)
    local ret = {}
    log.debug(utils.stringify_table((((device or {}).state_cache or {}))[component] or {}), component, true)
    local actual = get_with_early_return(
        device,
        'state_cache',
        component,
        'temperatureMeasurement',
        'temperature',
        'value'
    )
    local target = get_with_early_return(
        device,
        'state_cache',
        component,
        'thermostatHeatingSetpoint',
        'heatingSetpoint',
        'value'
    )
    local op_state = get_with_early_return(
        device,
        'state_cache',
        component,
        'thermostatOperatingState',
        'thermostatOperatingState',
        'value'
    )
    log.debug(string.format(
        'actual: %s, target: %s, op_state: %s',
        actual,
        target,
        op_state
    ))
    if actual ~= info.actual then
        log.debug(string.format('%s actual: %s ~= %s', component, actual, info.actual))
        ret.actual = info.actual
    end
    if target ~= info.target then
        log.debug(string.format('%s target: %s ~= %s', component, target, info.target))
        ret.target = info.target
    end
    local is_heating = op_state == HEATING
    if is_heating and info.target <= 0 then
        ret.is_heating = false
    elseif (not is_heating) and info.target > 0 then
        ret.is_heating = true
    elseif op_state == nil then
        ret.is_heating = info.target > 0
    end
    return ret
end

---Check the temperature of the bed and adjusts the state of the `bed` component
---@param device Device
---@param octopi Octopi
local function check_bed_state(octopi, device)
    log.trace('check_bed_state')
    local info, err = octopi:get_current_bed_temp()
    if not info then
        log.error('Failed to get bed temp', err)
        return TempState.all()
    end
    return compare_temp_states(device, 'bed', info)
end

---Check the state of the extruder temperature and adjust the main component state
--- * If the target temperature is > 0 this will emit a `heating` mode event
--- * If the target temperature is 0 this will emit an `idle` mode event
--- * If the target temp has changed it will emit a `heatingSetpoint` event
--- * If the actual temp has changed it will emit a `temperatureMeasurement` event
---@param device Device
---@param octopi Octopi
local function check_tool_state(octopi, device)
    log.trace('check_tool_state')
    local info, err = octopi:get_current_tool_temp()
    if not info then
        log.error('Faild to get tool temp', err)
        return TempState.all()
    end
    return compare_temp_states(device, 'tool', info)
end


--- Fetch the remote state from the octopi server and compare them to the
--- state_cache, populating any values that need to be updated
---@param octopi Octopi
---@param device Device
---@return DeviceState
function DeviceState.fetch(octopi, device)
    local switch_state, switch_err = check_switch_state(octopi, device)
    local bed_state, bed_err = check_bed_state(octopi, device)
    local tool_state, tool_err = check_tool_state(octopi, device)
    if not switch_state then
        log.error('Failed to fetch switch state', switch_err)
    end
    if not bed_state then
        log.error('Failed to fetch bed state', bed_err)
    end
    if not tool_state then
        log.error('Failed to fetch tool state', tool_err)
    end
    return setmetatable({
        switch = switch_state or {},
        bed = bed_state or {},
        tool = tool_state or {},
    }, DeviceState)
end

return DeviceState
