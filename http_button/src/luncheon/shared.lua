local Headers = require "luncheon.headers"
local utils = require "luncheon.utils"

---@enum Mode
--- Enumeration of the 2 sources of data
local Mode = {
    --- This is a Request or Response constructed via `source` it will rely on pulling
    --- new bytes from the `_source` function
    Incoming = "incoming",
    --- This is a Request or Response constructed via `new` it will assume all the
    --- properties have been filled manually
    Outgoing = "outgoing",
}
local SharedLogic = {}

---@param self Request|Response
---@return boolean|nil
---@return nil|string
function SharedLogic.parse_header(self)
    local line, err = self:_next_line()
    if not line then
        return nil, err
    end
    if self.headers == nil then
        self.headers = Headers.new()
    end
    if line == '' then
        return true
    else
        local s, e = self.headers:append_chunk(line)
        if not s then
            return nil, e
        end
    end
    return false
end

---
---@param self Request|Response
---@return string|nil
function SharedLogic.fill_headers(self)
    ---@diagnostic disable-next-line: invisible
    if self._parsed_headers then
        return
    end
    while true do
        local done, err = SharedLogic.parse_header(self)
        if err ~= nil then
            return err
        end
        if done then
            ---@diagnostic disable-next-line: invisible
            self._parsed_headers = true
            return
        end
    end
end

function SharedLogic.get_content_length(self)
    if not self._parsed_headers then
        local err = SharedLogic.fill_headers(self)
        if err then return nil, err end
    end
    if not self._content_length then
        assert(self.headers, debug.traceback())
        local cl = self.headers:get_one('content_length')
        if not cl then
            return
        end
        local n = math.tointeger(cl)
        if not n then
            return nil, 'bad Content-Length header'
        end
        self._content_length = n
    end
    return self._content_length
end

---Determine what type of body we are dealing with
---@param self Request|Response
---@return table|nil
---@return nil|string
function SharedLogic.body_type(self)
    local len, headers, enc, err
    len, err = SharedLogic.get_content_length(self)
    if not len and err then
        return nil, err
    end
    if len then
        return {
            type = "length",
            length = len
        }
    end
    headers, err = self:get_headers()
    if not headers then
        return nil, err
    end

    enc, err = headers:get_all("Transfer-Encoding")
    if not enc then
        return nil, err
    end
    for _, v in ipairs(enc) do
        if string.match(v, "chunked") then
            return {
                type = "chunked"
            }
        end
    end
    return {
        type = "close"
    }
end

---fill a content-length or close body
---@param self Request|Response
---@param len integer|nil
---@return string|nil
---@return nil|string
function SharedLogic.fill_len_or_close_body(self, len)
    ---@diagnostic disable-next-line: invisible
    local body, err = self._source(len or "*a")
    if not body then
        return nil, err
    end
    return body
end

---@param self Request|Response
---@return string|nil
---@return nil|string
function SharedLogic.fill_chunked_body_step(self)
    -- read chunk length with tailing new lines
    ---@diagnostic disable-next-line: invisible
    local len, err = self._source(3)
    if not len then
        return nil, err
    end
    local trimmed = string.sub(len, 1, 1)
    if trimmed == "0" then
        -- clear the last new line pair
        ---@diagnostic disable-next-line: invisible
        self._source(2)
        return nil, "___eof___"
    end
    local len2 = tonumber(trimmed, 16)
    if not len2 then
        return nil, "invalid number for chunk length"
    end
    ---@diagnostic disable-next-line: invisible
    local chunk, err = self._source(len2)
    if not chunk then
        return nil, err
    end
    -- clear new line
    ---@diagnostic disable-next-line: invisible
    self._source(2)
    return chunk
end

---@param self Request|Response
---@return string|nil
---@return nil|string
---@return nil|string
function SharedLogic.fill_chunked_body(self)
    local ret, chunk, err = "", nil, nil
    repeat
        chunk, err = SharedLogic.fill_chunked_body_step(self)
        ret = ret .. (chunk or "")
    until err
    if err == "___eof___" then
        return ret
    end
    return nil, err, ret
end

---
---@param self Request|Response
---@return nil|string
function SharedLogic.fill_body(self)
    if self.mode == Mode.Incoming
    ---@diagnostic disable-next-line: invisible
        and not self._received_body then
        local ty, err = SharedLogic.body_type(self)
        if not ty then
            return err
        end
        local body, err
        if ty.type == "close" or ty.type == "length" then
            body, err = SharedLogic.fill_len_or_close_body(self, ty.length)
            if not body then
                return err
            end
        else
            body, err = SharedLogic.fill_chunked_body(self)
            if not body then
                return err
            end
        end
        self.body = body
        ---@diagnostic disable-next-line: invisible
        self._received_body = true
    end
end

---
---@param self Request|Response
---@return string|nil
---@return nil|string
function SharedLogic.get_body(self)
    local err = SharedLogic.fill_body(self)
    if err then
        return nil, err
    end
    return self.body
end

---@param self Request|Response
---@return Headers|nil
---@return nil|string
function SharedLogic.get_headers(self)
    ---@diagnostic disable-next-line: invisible
    if self.mode == Mode.Incoming and not self._parsed_headers then
        local err = SharedLogic.fill_headers(self)
        if err ~= nil then
            return nil, err
        end
    end
    return self.headers
end

---Serialize the pre body text of a request/response including the trailing new line
---@param t Request|Response
function SharedLogic.serialize_pre_body(t)
    local first, headers, headers_str, err
    first, err = t:_serialize_preamble()
    if not first then
        return nil, err
    end
    headers, err = t:get_headers()
    if not headers then
        return nil, err
    end
    headers_str, err = headers:serialize()
    if not headers_str then
        return nil, err
    end
    return first
        .. '\r\n'
        .. headers_str
        .. '\r\n'
end

--- Serailize the provide Request or Response into a string with new lines
---@param t Request|Response
---@return string|nil result The serialized string if nil an error occured
---@return nil|string err If not nil the error
function SharedLogic.serialize(t)
    local pre, body, e
    if t.mode == Mode.Incoming then
        e = SharedLogic.fill_headers(t)
        if e then return nil, e end
        e = SharedLogic.fill_body(t)
        if e then return nil, e end
    end
    pre, e = SharedLogic.serialize_pre_body(t)
    if not pre then
        return nil, e
    end
    body, e = t:get_body()
    if not body then
        return nil, e
    end
    return pre .. body
end

function SharedLogic.iter(self)
    local state = 'start'
    local suffix = '\r\n'
    local header_iter = self:get_headers():iter()
    local value, body, body_type, err
    return function()
        if state == 'start' then
            state = 'headers'
            return self:_serialize_preamble() .. suffix
        end
        if state == 'headers' then
            local header = header_iter()
            if not header then
                state = 'body'
                return suffix
            end
            return header .. suffix
        end
        if state == 'body' then
            if self.mode == Mode.Incoming then
                if not body_type then
                    body_type, err = SharedLogic.body_type(self)
                    if not body_type then
                        return nil, err
                    end
                end
                if body_type.type == "chunked" then
                    local chunk, err = SharedLogic.fill_chunked_body_step(self)
                    if err == "___eof___" then
                        state = 'complete'
                        return nil
                    end
                    return chunk, err
                end
                local line, err = self:_next_line()
                if err == 'closed' or not line then
                    state = 'complete'
                    return nil
                end
                return line, err
            end
            
            if not body then
                local b, err = self:get_body()
                if not b then
                    return nil, err
                end
                state = 'body'
                body = b
            end
            value, body = utils.next_line(body, true)
            if not value then
                state = 'complete'
                return body
            end
            return value
        end
    end
end

---Send the first line of the Request|Response
---@param self Request|Response
---@return integer|nil
---@return string|nil
function SharedLogic.send_preamble(self)
    if self._send_state.stage ~= 'none' then
        return 1 --already sent
    end
    local line = self:_serialize_preamble() .. '\r\n'
    local s, err = utils.send_all(self.socket, line)
    if not s then
        return nil, err
    end
    self._send_state.stage = 'header'
    return 1
end

---Collect the preamble and headers to the provided limit
---@param self Request|Response
---@param max integer
---@return string
---@return integer
function SharedLogic.build_chunk(self, max)
    local buf = ""
    if self._send_state.stage == "none" then
        buf = self:_serialize_preamble() .. "\r\n"
        self._send_state.stage = "header"
    end
    if #buf >= max then
        return buf, 0
    end
    ---@diagnostic disable-next-line: invisible
    local inner_headers = self.headers._inner
    while self._send_state.stage == "header" do
        local key, value = next(inner_headers, self._send_state.last_header)
        if not key then
            buf = buf .. "\r\n"
            self._send_state = {
                stage = 'body',
                sent = 0,
            }
            break
        end
        local line = Headers.serialize_header(key, value) .. '\r\n'
        if #line + #buf > max then
            return buf, 0
        end
        self._send_state.last_header = key
        buf = buf .. line
    end
    local body_len = 0
    if #buf < max then
        body_len = max - #buf
        local start_idx = self._send_state.sent + 1
        local end_idx = start_idx + body_len
        local chunk = string.sub(self.body, start_idx, end_idx)
        body_len = #chunk
        buf = buf .. chunk
    end
    return buf, body_len
end

---Pass a single header line into the sink functions
---@param self Request|Response
---@return integer|nil If not nil, then successfully "sent"
---@return nil|string If not nil, the error message
function SharedLogic.send_header(self)
    if self._send_state.stage == 'none' then
        return self:send_preamble()
    end
    if self._send_state.stage == 'body' then
        return nil, 'cannot send headers after body'
    end
    ---@diagnostic disable-next-line: invisible
    local key, value = next(self.headers._inner, self._send_state.last_header)
    if not key then
        local s, e = utils.send_all(self.socket, '\r\n')
        if not s then
            return nil, e
        end
        self._send_state = {
            stage = 'body',
            sent = 0,
        }
        return 1
    end
    local line = Headers.serialize_header(key, value) .. '\r\n'
    local s, e = utils.send_all(self.socket, line)
    if not s then
        return nil, e
    end
    self._send_state.last_header = key
    return 1
end

---Slice a chunk of at most 1024 bytes from `self.body` and pass it to
---the sink
---@return integer|nil if not nil, success
---@return nil|string if not nil and error message
function SharedLogic.send_body_chunk(self)
    local chunk, body_len = SharedLogic.build_chunk(self, 1024)
    local s, e, i = utils.send_all(self.socket, chunk)
    if not s then
        return nil, e
    end
    self._send_state.sent = self._send_state.sent + body_len
    return 1
end

---Final send of a request or response
---@param self Request|Response
---@param bytes string|nil
---@param skip_length boolean|nil
function SharedLogic.send(self, bytes, skip_length)
    if bytes then
        self.body = self.body .. bytes
    end
    if self._send_state.stage ~= 'body' and not skip_length then
        self:set_content_length(#self.body)
    end
    while self._send_state.stage ~= 'body'
        or (self._send_state.sent or 0) < #self.body do
            
        local s, e = SharedLogic.send_body_chunk(self)
        if not s then
            return nil, e
        end
    end
    return 1
end

return {
    SharedLogic = SharedLogic,
    Mode = Mode,
}
