local capabilities = require 'st.capabilities'
local Driver = require 'st.driver'
local log = require 'log'

local discovery = require 'disco'
local server = require 'server'
local utils = require 'st.utils'

local currentUrlID = "honestadmin11679.currentUrl"
local currentUrl = capabilities[currentUrlID]

-- These handlers are primarily to make the log traffic
-- as chatty as possible
local function device_added(driver, device)
    local url = driver:get_url()
    if url then
        device:emit_event(currentUrl.currentUrl(url))
    end
    log.trace('Added http_button ' .. device.id)
end

local function device_init(driver, device)
    local url = driver:get_url()
    if url then
        device:emit_event(currentUrl.currentUrl(url))
    end
    log.trace('Init\'d http_button ' .. device.id)
end

local function device_removed(driver, device)
    log.trace('Removed http_button ' .. device.id)
end

local function info_changed(driver, device, event, ...)
    log.trace('Info Changed ', device.id, event, ...)
end

local driver = Driver('http_button', {
    lifecycle_handlers = {
        init = device_init,
        added = device_added,
        deleted = device_removed,
        infoChanged = info_changed,
    },
    discovery = discovery.disco_handler,
})

--- Handler for the `push` event
---@param device Device
function driver:push(device)
    device:emit_event(capabilities.button.button.pushed())
    log.debug('http_button '.. device.id .. ' pushed')
end

--- Handler for the `held` event
---@param device Device
function driver:hold(device)
    device:emit_event(capabilities.button.button.held())
    log.debug('http_button '.. device.id .. ' held')
end

--- The primary handler of http requests associated with an id
---
---@param event string The event to fire, either `push` or `held`
---@param device Device the device id to emit that event for
function driver:trigger_event(event, device)
    local msg
    local err
    if event == 'push' then
        local success = pcall(driver.push, self, device)
        if success then
            msg = 'sent push event for ' .. device.id
        else
            err = 'failed to send push event for ' .. device.id
        end
        log.info(msg or err)
        return msg, err
    end
    if event == 'held' then
        local success = pcall(driver.held, self, device)
        if success then
            msg = 'sent push event for ' .. device.id
        else
            err = 'failed to send held event for ' .. device.id
        end
        log.info(msg or err)
        return msg, err
    end
    return nil, "unknown event: " .. event
end

function driver:get_url()
    if self.server == nil or self.server.port == nil then
        log.info('waiting for server to start')
        return
    end
    local ip = self.server:get_ip()
    local port = self.server.port
    if ip == nil then
        return
    end
    return string.format("http://%s:%s", ip, port)
end

--- Print the current listening IP and port number
function driver:print_listening_message()
    local url = self:get_url()
    if url then
        log.info(string.format('listening on %s', url))
    end
end

function driver:emit_current_url()
    local url = self:get_url()
    if url then
        for i,device in ipairs(self:get_devices()) do
            print("device", i, device)
            device:emit_event(currentUrl.currentUrl(url))
        end
    else
        self:call_with_delay(1, self.emit_current_url)
    end
end

driver.ping_loop = driver:call_on_schedule(60, driver.print_listening_message)
driver:call_with_delay(0, driver.emit_current_url)

server(driver)
driver:print_listening_message()

driver:run()
log.warn('Exiting http_button')
