local net_url = require 'net.url'
local Headers = require 'luncheon.headers'
local utils = require 'luncheon.utils'
local shared = require 'luncheon.shared'

---@class Request
---
---An HTTP Request
---
---@field public method string the HTTP method for this request
---@field public url table The parsed url of this request
---@field public http_version string The http version from the request first line
---@field public headers Headers The HTTP headers for this request
---@field public body string The contents of the request's body
---@field public socket table Lua socket for receiving/sending
---@field private _source fun(pat:string|number|nil):string
---@field private _parsed_headers boolean
---@field private _received_body boolean
---@field public mode Mode
local Request = {}
Request.__index = Request

--#region Parser

---Parse the first line of an HTTP request
---@param line string
---@return {method:string,url:table,http_version:string}|nil table
---@return nil|string
function Request._parse_preamble(line)
    local start, _, method, path, http_version = string.find(line, '([A-Z]+) (.+) HTTP/([0-9.]+)')
    if not start then
        return nil, string.format('Invalid http request first line: "%s"', line)
    end
    return {
        method = method,
        url = net_url.parse(path),
        http_version = http_version,
        body = nil,
        headers = nil,
    }
end

---Construct a request from a source function
---@param source fun(pat:string|number|nil):string|nil,nil|string
---@return Request|nil request
---@return nil|string error
function Request.source(source)
    if not source then
        return nil, 'cannot create request with nil source'
    end
    local r = {
        _source = source,
        _parsed_headers = false,
        mode = shared.Mode.Incoming,
    }
    setmetatable(r, Request)
    local line, acc_err = r:_next_line()
    if acc_err then
        return nil, acc_err
    end
    local pre, pre_err = Request._parse_preamble(line)
    if not pre then
        return nil, pre_err
    end
    r.http_version = pre.http_version
    r.method = pre.method
    r.url = pre.url
    return r
end

---Create a new Request with a lua socket
---@param socket table tcp socket
---@return Request|nil request with the first line parsed
---@return nil|string if not nil an error message
function Request.tcp_source(socket)
    local utils = require 'luncheon.utils'
    local ret, err = Request.source(
        utils.tcp_socket_source(socket)
    )
    if not ret then
        return nil, err
    end
    ret.socket = socket
    return ret
end

---Create a new Request with a lua socket
---@param socket table udp socket
---@return Request|nil
---@return nil|string
function Request.udp_source(socket)
    local utils = require 'luncheon.utils'
    local ret, err =  Request.source(
        utils.udp_socket_source(socket)
    )
    if not ret then
        return nil, err
    end
    ret.socket = socket
    return ret
end

---Get the headers for this request
---parsing the incoming stream of headers
---if not already parsed
---@return Headers|nil
---@return string|nil
function Request:get_headers()
    return shared.SharedLogic.get_headers(self)
end

---Read a single line from the socket
---@return string|nil, string|nil
function Request:_next_line()
    local line, err = self._source('*l')
    return line, err
end

---Get the contents of this request's body
---if not yet received, this will read the body
---from the socket
---@return string|nil, string|nil
function Request:get_body()
    return shared.SharedLogic.get_body(self)
end

---Get the value from the Content-Length header that should be present
---for all http requests
---@return number|nil, string|nil
function Request:get_content_length()
    return shared.SharedLogic.get_content_length(self)
end

---@deprecated see get_content_length
function Request:content_length()
    return self:get_content_length()
end

--#endregion Parser

--#region Builder
---Construct a request Builder
---@param method string|nil an http method string
---@param url string|table|nil the path for this request as a string or as a net_url table
---@param socket table|nil
---@return Request
function Request.new(method, url, socket)
    if type(url) == 'string' then
        url = net_url.parse(url)
    end
    return setmetatable({
        method = string.upper(method or 'GET'),
        url = url or net_url.parse('/'),
        headers = Headers.new(),
        http_version = '1.1',
        body = '',
        socket = socket,
        _send_state = {
            stage = 'none',
        },
        _parsed_header = true,
        mode = shared.Mode.Outgoing,
    }, Request)
end

---Add a header to the internal map of headers
---note: this is additive, so adding X-Forwarded-For twice will
---cause there to be multiple X-Forwarded-For entries in the serialized
---headers
---@param key string The Header's key
---@param value string The Header's value
---@return Request
function Request:add_header(key, value)
    if type(value) ~= 'string' then
        value = tostring(value)
    end
    self.headers:append(key, value)
    return self
end

---Replace or append a header to the internal headers map
---
---note: this is not additive, any existing value will be lost
---@param key string
---@param value any If not a string will call tostring
---@return Request
function Request:replace_header(key, value)
    if type(value) ~= 'string' then
        value = tostring(value)
    end
    self.headers:replace(key, value)
    return self
end

---Set the Content-Type header for this request
---convenience wrapper around self:replace_header('content_type', len)
---@param ct string The mime type to add as the Content-Type header's value
---@return Request|nil
---@return nil|string
function Request:set_content_type(ct)
    if type(ct) ~= 'string' then
        return nil, string.format('mime type must be a string, found %s', type(ct))
    end
    self:replace_header('content_type', ct)
    return self
end

---Set the Content-Length header for this request
---convenience wrapper around self:replace_header('content_length', len)
---@param len number The Expected length of the body
---@return Request
function Request:set_content_length(len)
    self:replace_header('content_length', tostring(len))
    return self
end

---append the provided chunk to this Request's body
---@param chunk string The text to add to this request's body
---@return Request
function Request:append_body(chunk)
    self.body = (self.body or '') .. chunk
    self:set_content_length(#self.body)
    return self
end

---Private method for serializing the url property into a valid URL string suitable
---for the first line of an HTTP request
---@return string
function Request:_serialize_path()
    if type(self.url) == 'string' then
        self.url = net_url.parse(self.url)
    end
    local path = self.url.path or '/'
    if not self.url.query or not next(self.url.query) then
        return path
    end
    return path .. '?' .. net_url.buildQuery(self.url.query)
end

---Private method for serializing the first line of the request
---@return string
function Request:_serialize_preamble()
    return string.format('%s %s HTTP/%s', string.upper(self.method), self:_serialize_path(), self.http_version)
end

---Serialize this request into a single string
---@return string|nil
---@return nil|string
function Request:serialize()
    return shared.SharedLogic.serialize(self)
end

---Serialize this request as a lua iterator that will
---provide the next line (including new line characters).
---This will split the body on any internal new lines as well
---@return fun():string
function Request:iter()
    return shared.SharedLogic.iter(self)
end

--#endregion Builder

--#region sink

---Serialize and pass the first line of this Request into the sink
---@return integer|nil if not nil, success
---@return nil|string if not nil and error message
function Request:send_preamble()
    return shared.SharedLogic.send_preamble(self)
end

---Pass a single header line into the sink functions
---@return integer|nil If not nil, then successfully "sent"
---@return nil|string If not nil, the error message
function Request:send_header()
    return shared.SharedLogic.send_header(self)
end

---Slice a chunk of at most 1024 bytes from `self.body` and pass it to
---the sink
---@return integer|nil if not nil, success
---@return nil|string if not nil and error message
function Request:send_body_chunk()
    return shared.SharedLogic.send_body_chunk(self)
end

---Serialize and pass the request chunks into the sink
---@param bytes string|nil the final bytes to append to the body
---@return integer|nil If not nil sent successfully
---@return nil|string if not nil the error message
function Request:send(bytes, skip_length)
    return shared.SharedLogic.send(self, bytes, skip_length)
end

--#endregion

return Request
