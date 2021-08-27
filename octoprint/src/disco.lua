local socket = require 'socket'
local http = require 'socket.http'
local json = require 'dkjson'
local log = require 'log'
local xml_parse = require 'xml_parse'
local utils = require 'st.utils'

local listen_ip = "0.0.0.0"
local listen_port = 0

local multicast_ip = "239.255.255.250"
local multicast_port = 1900
local multicast_msg = table.concat({
    'M-SEARCH * HTTP/1.1',
    string.format('HOST: %s:%s', multicast_ip, multicast_port),
    'MAN: ' .. '"ssdp:discover"',
    'ST: ' .. 'ssdp:all',
}, '\r\n')

---@class SsdpDevice
---@field id string The DNI for this Octoprint server
---@field url string The URL for this server
local SsdpDevice = {}

--- Add a new device to this driver
---
---@param driver Driver The driver instance to use
---@param device_id string The uuid provided by the ssdp lookup
---@param device_number number|nil If populated this will be used to generate the device name/label if not, `get_device_list` will be called to provide this value
local function add_device(driver, device_id, device_number)
    local device_id = string.match(device_id, '[^%s]+')
    log.trace('add_device', device_id, device_number)
    if device_number == nil then
        log.debug('determining current device count')
        local device_list = driver.device_api.get_device_list()
        device_number = #device_list
    end
    local device_name = 'Octopi ' .. device_number
    log.debug('adding device ' .. device_name)

    local device_info = {
        type = 'LAN',
        deviceNetworkId = device_id,
        label = device_name,
        profileReference = 'octopi.v1',
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

--- Query the current network for ssdp/unpnp devices
local function ssdp_query()
    log.debug('ssdp_query')
    local success, err
    local s = assert(socket.udp())
    s:setsockname(listen_ip, listen_port)
    success, err = s:sendto(multicast_msg, multicast_ip, multicast_port)
    if not success then
        log.error('Failed to sent multicast_msg', err)
        return nil, err
    end
    s:settimeout(1)
    local devices = {}
    while true do
        local resp
        resp, err = s:receivefrom()
        if err == 'timeout' then
            log.debug('timed out')
            break
        end
        log.trace('received udp message', resp)
        for part in string.gmatch(resp, 'Location: ([^%s]+)') do
            table.insert(devices, {
                discovery_url = part,
            })
        end
    end
    local ret = {}
    for _, device in ipairs(devices) do
        log.debug('requesting', device.discovery_url)
        local xml, status = http.request(device.discovery_url)
        if xml then
            log.debug('deserializing xml')
            local id, url, manu = xml_parse(xml)
            if not id then
                log.error('Failed to deserialize xml: ', url, utils.stringify_table(manu))
                goto continue
            end
            log.debug('info:', id, url, manu)
            if manu == 'http://www.octoprint.org/' then
                device.id = id
                device.url = url
                table.insert(ret, device)
            end
        else
            log.error('failed to request discovery xml', status)
        end
        ::continue::
    end
    return ret
end

--- A discovery pass that will discover exactly 1 device
--- for a driver. I any devices are already associated with
--- this driver, no devices will be discovered
---
---@param driver Driver the driver name to use when discovering a device
---@param opts table the discovery options
---@param cont function function to check if discovery should continue
local function disco_handler(driver, opts, cont)
    driver.datastore.urls = driver.datastore.urls or {}
    local known_devices = {}
    local devices_list = driver:get_devices()
    local new_num = #devices_list
    for _, device in ipairs(devices_list) do
        known_devices[device.device_network_id] = true
    end
    log.trace('starting discovery')
    local ssdp_devices = ssdp_query()
    for _, device in ipairs(ssdp_devices) do
        if not known_devices[device.id] then
            known_devices[device.id] = true
            log.debug('Found unknown device', device.id)
            local _, _, err = add_device(driver, device.id, new_num)
            if err then
                log.error('Error adding device', err)
            else
                known_devices[device.id] = true
            end
            driver.datastore.printers[device.id] = device
            new_num = new_num + 1
        end
    end
end



return {
    disco_handler = disco_handler,
    add_device = add_device,
    ssdp_query = ssdp_query,
}
