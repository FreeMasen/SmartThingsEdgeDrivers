local json = require 'st.json'
local log = require 'log'
local utils = require 'st.utils'

--- Add a new device to this driver
---
---@param driver Driver The driver instance to use
---@param device_number number|nil If populated this will be used to generate the device name/label if not, `get_device_list`
---                                     will be called to provide this value
local function add_device(driver, device_number)
    log.trace('add_devices')
    if device_number == nil then
        log.debug('determining current device count')
        local device_list = driver.device_api.get_device_list()
        device_number = #device_list
    end
    local device_name = 'Ch Hand ' .. device_number
    log.debug('adding device ' .. device_name)
    local device_id = utils.generate_uuid_v4()
    local device_info = {
        type = 'LAN',
        deviceNetworkId = device_id,
        label = device_name,
        profileReference = 'ch_hand.v1',
        vendorProvidedName = device_name,
    }
    local device_info_json = json.encode(device_info)
    local success, msg = driver.device_api.create_device(device_info_json)
    if success then
        log.debug('successfully created device')
        return device_name, device_id
    end
    log.error(string.format('unsuccessful create_device %s', msg))
    return nil, nil, msg
end

--- A discovery pass that will discover exactly 1 device
--- for a driver. I any devices are already associated with
--- this driver, no devices will be discovered
---
---@param driver Driver the driver name to use when discovering a device
---@param opts table the discovery options
---@param cont function function to check if discovery should continue
local function disco_handler(driver, opts, cont)
    log.trace('disco')

    if cont() then
        local device_list = driver.device_api.get_device_list()
        log.trace('starting discovery')
        if #device_list > 0 then
            log.debug('stopping discovery with ' .. #device_list .. ' devices')
            return
        end
        log.debug('Adding first ' .. driver.NAME .. ' device')
        local device_name, device_id, err = add_device(driver, #device_list)
        if err ~= nil then
            log.error(err)
            return
        end
        log.info('added new device ' .. device_name)
    end
end



return {
    disco_handler = disco_handler,
    add_device = add_device,
}
