local cosock = require "cosock"
local http = cosock.asyncify 'socket.http'
local ltn12 = require 'ltn12'
local socket = cosock.socket
local json = require 'dkjson'
local log = require 'log'

---@class TemperatureInfo
---@field public actual number The current measured temperature
---@field public target number The current target temp
---@field public offset number The printer's temp offset
local TemperatureInfo = {}

---@class Octopi
---@field public id string UUID for this device
---@field public name string Label for this device
---@field public url string Base URL for the octopi server
---@field public user string The username to request an auth token
---@field public api_key string The auth token
local OctoPi = {}
OctoPi.__index = OctoPi

---Private endpoint constants
local __endpoints = {
    request_auth = 'plugin/appkeys/request',
    poll_auth = 'plugin/appkeys/probe',
    job = 'api/job',
    tool = 'api/printer/tool',
    bed = 'api/printer/bed',
    connection = 'api/connection',
}

---Create a new Octopi instance
---@param id string
---@param name string
---@param url string
---@param user string
---@param api_key string
---@return Octopi
function OctoPi.new(id, name, url, user, api_key)
    return setmetatable(
        {
            id = id,
            name = name,
            url = url,
            user = user,
            api_key = api_key,
            pending_url = nil,
        },
        OctoPi
    )
end

---Check if this octopi instance has an api_key
---@return boolean
function OctoPi:has_key()
    return self.api_key and #self.api_key > 0
end

---Check if this octopi instance has a user
---@return boolean
function OctoPi:has_user()
    return self.user and #self.user > 0
end

---Follow the auth plugin workflow to gain an api_key
---@return integer|string?, string? @Returns the api_key when the auth_workflow completes
function OctoPi:gain_authorization()
    log.trace('OctoPi:gain_authorization')
    if self:has_key() then
        log.debug('previously authorized')
        return self.api_key
    end
    if not self:has_user() then
        return nil, 'No user to grant permission'
    end
    local url = string.format('%s%s', self.url, __endpoints.request_auth)
    local body = json.encode({
        app = 'SmartThings Octopi Driver',
        user = self.user
    })
    log.debug('Sending request', url, body)

    local success, status_or_err, headers, status_msg = http.request{
        url = url,
        method = 'POST',
        source = ltn12.source.string(
            body
        ),
        headers = {
            ['Content-Type'] = 'application/json',
            ['Content-Length'] = #body,
        }
    }
    if status_or_err and status_or_err == 400 then
        return nil, string.format('Failed to request auth %s %s', status_or_err, status_msg)
    end
    if status_or_err ~= 201 then
        return nil, string.format('Failed to request auth %s, %s', status_or_err, status_msg)
    end
    self.pending_url = headers.location
    local start = socket.gettime()
    for i=1, 60 do
        log.info('polling for approval')
        local key, err = self:_poll_for_approval()
        if not key then
            return nil, err
        end
        if key ~= 'pending' then
            self.pending_url = nil
            self.api_key = key
            return key
        end
        log.info('no approval yet, sleeping for 1')
        socket.sleep(1)
    end
    return self:gain_authorization()
end

---Poll the auth endpoint for approval
---@return string?, string? @comment the string 'pending' if not yet approved, the api key if approved
function OctoPi:_poll_for_approval()
    log.trace('OctoPi:_poll_for_approval')
    if not self.pending_url then
        log.warn('Attempt to probe for approval without pending_url')
        return nil, 'Attempt to probe for approval without pending_url'
    end
    log.debug('requesting', self.pending_url)
    local body, s_or_e, _headers, status_msg = http.request(self.pending_url)
    if not body then
        return nil, s_or_e
    end
    log.debug('response: ', s_or_e, status_msg)
    if s_or_e == 404 then
        self.pending_url = nil
        return nil, 'Request timed out or denied', body
    end
    if s_or_e == 202 then
        return 'pending'
    end
    assert(s_or_e == 200, string.format('Invalid status code returned: %s %s', s_or_e, status_msg))
    log.debug('Successfully got approval')
    return json.decode(body).api_key
end

---Check if the printer is actively working on a job
---@return string? @`nil` if an error occurs in the request. The state 'Printing' if active
---@return string? @The error message
function OctoPi:check_state()
    log.trace('OctoPi:check_state')
    if (not self.api_key or #self.api_key == 0) then
        if self.pending_url then
            return nil, 'pending authorization'
        end
        local key, err = self:gain_authorization()
        if not key then
            log.error('Error gaining auth', err)
            return nil, 'Unauthorized'
        end
        self.api_key = key
    end
    local body, err, err_body = self:_get_request(__endpoints.job)
    if not body then
        log.error('request failed', err_body)
        return nil, err
    end
    local job_info, err = json.decode(body)
    if not job_info then
        return nil, 'failed to deserialize job info ' .. tostring(err)
    end
    return job_info.state
end

---Cancel the current job
---@return string? @If not `nil`, an error message
---@return string? @If not `nil`, an error message
function OctoPi:cancel_job()
    log.trace('OctoPi:cancel_job')
    if not self.api_key then
        return nil, 'Unauthorized'
    end
    local body = json.encode({
        command = "cancel"
    })
    return self:_post_request(__endpoints.job, {
        command = 'cancel'
    })
end

---Adjust the temperature of the extruder
---@param new_temp number The new temperature
---@return number? @The temperature provided
---@return string? @An error message
function OctoPi:adjust_tool_temp(new_temp)
    local success, err = self:_post_request(__endpoints.tool,
        {
            command = 'target',
            targets = {
                tool0 = new_temp or 0
            }
        }
    )
    if success then
        return new_temp
    end
    return nil, err
end

---Get the current temperature of the printer's extruder
---@return TemperatureInfo? @The object of the extruder's properties
---@return string? @An error message if this fails
function OctoPi:get_current_tool_temp()
    local body, err, err_body = self:_get_request(__endpoints.tool)
    if not body then
        log.error(err)
        log.trace(err_body)
        return nil, err
    end
    local hist = json.decode(body)
    return hist.tool0
end

---Adjust the temperature of the bed
---@param new_temp number The new target temperature
---@return number? @If successful, the new target temp
---@return string? @If unsuccessful, the error message
function OctoPi:adjust_bed_temp(new_temp)
    local success, err = self:_post_request(__endpoints.bed,
        {
            command = 'target',
            target = new_temp or 0,
        }
    )
    if success then
        return new_temp
    end
    return nil, err
end

---Get the current bed temperature
---@return TemperatureInfo? @The object describing the bed's temperature
---@return string? @If the request fails, the error message
---@return string? @If the request is successful but the wrong status, the response body
function OctoPi:get_current_bed_temp()
    local body, err, err_body = self:_get_request(__endpoints.bed)
    if not body then
        return nil, err, err_body
    end
    local info = json.decode(body)
    return info.bed
end

---Attempt to connect Octopi to the 3d printer via the serial properties
---@return number|nil @1 if successful
---@return string|nil @The error message
---@return string|nil @The http body if available
function OctoPi:_connect()
    local body, err, err_body = self:_post_request(__endpoints.connection, {
        command = 'connect',
    }, true)
    if not body then
        return nil, err, err_body
    end
    return 1
end

---Perform an http get request after authenticated
---@param endpoint string The endpoint to add to self.url 
---@return string? @The http request body
---@return string? @If the request fails, the error message
---@return string? @If the request is successful but the status isn't 200, the response body
function OctoPi:_get_request(endpoint, no_retry)
    log.trace('OctoPi:_get_request')
    if not self.api_key then
        self:gain_authorization()
    end
    local body_t = {}

    local success, status_or_err, _headers, status_msg = http.request{
        url = string.format('%s%s', self.url, endpoint),
        method = 'GET',
        sink = ltn12.sink.table(body_t),
        headers = {
            ['X-Api-Key'] = self.api_key,
        },
    }

    if not success then
        return nil, 'failed to request state ' .. tostring(status_or_err)
    end
    if status_or_err == 409 and not no_retry then
        self:_connect()
        return self:_get_request(endpoint, body_t, true)
    end
    if status_or_err ~= 200 then
        log.error('response status', status_msg)
        return nil, status_msg, table.concat(body_t, '')
    end
    return table.concat(body_t, '')
end

---Make an http POST request
---@param endpoint string The endpoint to append to the self.url
---@param body_t table? If not `nil` the table that should be converted into the json request body
---@param no_retry boolean? If falsy, if the request returns a 409, an attempt will be made to connect octopri to the printer
---@return string? @If successful, the http response body
---@return string? @If unsuccessful, the error message
function OctoPi:_post_request(endpoint, body_t, no_retry)
    log.trace('OctoPi:_post_request')
    if not self.api_key then
        self:gain_authorization()
    end
    local body = body_t and json.encode(body_t) or ''
    local res_t = {}
    local success, s_or_e, _headers, status_msg = http.request {
        url = string.format('%s%s', self.url, endpoint),
        method = 'POST',
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(res_t),
        headers = {
            ['Content-Type'] = 'application/json',
            ['Content-Length'] = #body,
            ['X-Api-Key'] = self.api_key,
        }
    }
    if s_or_e == 200 then
        return table.concat(res_t, '')
    end
    if s_or_e == 204 then
        return 1
    end
    if s_or_e == 409 and not no_retry then
        self:_connect()
        return self:_post_request(endpoint, body_t, true)
    end
    log.trace(string.format('POST RESPONSE "%s" "%s"'), table.concat(body or {'NO BODY'}, ''))
    if status_msg then
        return nil, string.format('%s: %s', s_or_e, status_msg)
    end
    return nil, s_or_e
end

return OctoPi
