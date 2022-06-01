local start = os.time()
local capabilities = require 'st.capabilities'
local Driver = require 'st.driver'
local log = require 'log'

local discovery = require 'disco'
local server = require 'server'
local utils = require 'st.utils'

-- These handlers are primarily to make the log traffic
-- as chatty as possible
local function device_added(driver, device)
    log.trace('Added http_button ' .. device.id)
end

local function device_init(driver, device)
    log.trace('Init\'d http_button ' .. device.id)
end

local function device_removed(driver, device)
    log.trace('Removed http_button ' .. device.id)
end

local function info_changed(driver, device, event)
    log.trace('Info Changed ', device.id, event)
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
    device:emit_event(capabilities.button.button.pushed({state_change = true}))
    log.debug('http_button '.. device.id .. ' pushed')
end

--- Handler for the `held` event
---@param device Device
function driver:hold(device)
    device:emit_event(capabilities.button.button.held({state_change = true}))
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

--- This will fire when the socket is read for an `accept` call
function driver:server_tick()
    if self.server ~= nil then
        self.server:tick()
    end
end

--- Print the current listening IP and port number
function driver:print_listening_message()
    if self.server == nil or self.server.port == nil then
        log.info('waiting for server to start')
        return
    end
    local ip = self.server:get_ip()
    local port = self.server.port
    if ip == nil then
        log.info(string.format('listening on port %s', port))
        return
    end
    log.info(string.format('listening on http://%s:%s', ip, self.server.port))
end

driver.ping_loop = driver:call_on_schedule(5, driver.print_listening_message)

server(driver)

local loaded = os.time()
driver:call_with_delay(0, function()
    print("Time to load:", loaded - start)
end)
driver:run()
log.warn('Exiting http_button')
