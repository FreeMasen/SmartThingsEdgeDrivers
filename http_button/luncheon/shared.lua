---@diagnostic disable: invisible
local Headers = require "luncheon.headers"
local utils = require "luncheon.utils"
local log = require "log"

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

---Append a header to the `Headers` with the matching name
---@param self Request|Response
---@param k string
---@param v string|any
---@param name string
function SharedLogic.append_header(self, k, v, name)
  if not self[name] then
    self[name] = Headers.new()
  end
  if type(v) ~= "string" then
    v = tostring(v)
  end
  self[name]:append(k, v)
end

---Append a header to the `Headers` with the matching name
---@param self Request|Response
---@param k string
---@param v string|any
---@param name string
function SharedLogic.replace_header(self, k, v, name)
  if not self[name] then
    self[name] = Headers.new()
  end
  if type(v) ~= "string" then
    v = tostring(v)
  end
  self[name]:replace(k, v)
end

---@param self Request|Response
---@param key string|nil The header map key to use, defaults to "headers"
---@return boolean|nil
---@return nil|string
function SharedLogic.read_header(self, key)
  key = key or "headers"
  local line, err = self:_next_line()
  if not line then
    return nil, err
  end
  if self[key] == nil then
    self[key] = Headers.new()
  end
  if line == "" then
    return true
  else
    local s, e = self[key]:append_chunk(line)
    if not s then
      return nil, e
    end
  end
  return false
end

---
---@param self Request|Response
---@return string|nil
function SharedLogic.fill_headers(self, key)
  key = key or "headers"
  local parsed_key = string.format("_parsed_%s", key)
  if self[parsed_key] then
    return
  end
  while true do
    local done, err = SharedLogic.read_header(self, key)
    if err ~= nil then
      return err
    end
    if done then
      self[parsed_key] = true
      return
    end
  end
end

function SharedLogic.get_content_length(self)
  if not self._parsed_headers then
    local err = SharedLogic.fill_headers(self, "headers")
    if err then return nil, err end
  end
  if not self._content_length then
    local cl = self.headers:get_one("content_length")
    if not cl then
      return
    end
    local n = math.tointeger(cl)
    if not n then
      return nil, "bad Content-Length header"
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

  enc = headers:get_all("transfer_encoding")
  local ty = "close"
  if not enc then
    return {
      type = ty,
    }
  end
  for _, v in ipairs(enc) do
    if string.match(v, "chunked") then
      ty = "chunked"
      break
    end
  end
  local trailers = false
  if ty == "chunked" then
    local trailer = headers:get_all("trailer")
    trailers = trailer and #trailer > 0 and #trailer[1] > 0
  end
  return {
    type = ty,
    trailers = trailers
  }
end

---fill a body based on content-length
---@param self Request|Response
---@param len integer
---@return string|nil
---@return nil|string
function SharedLogic.fill_fixed_length_body(self, len)
  local body, err = self._source(len)
  if not body then
    return nil, err
  end
  return body
end

---fill a body by reading until the socket is closed
---@param self Request|Response
---@return string|nil
---@return nil|string
function SharedLogic.fill_closed_body(self)
  local body, err = self._source("*a")
  if not body then
    return nil, err
  end
  return body
end

---@param self Request|Response
---@return string|nil
---@return nil|string
function SharedLogic.fill_chunked_body_step(self)
  -- read chunk length with trailing new lines

  local len, err = self._source("*l")
  if not len then
    return nil, err
  end
  local trimmed = string.match(len, "^[^;]+")
  for extension in string.gmatch(len, ";([^;]+)") do
    log.warn(string.format("found unsupported extension: %q", extension))
  end
  if trimmed == "0" then
    return nil, "___eof___"
  end
  local len2 = tonumber(trimmed, 16)
  if not len2 then
    return nil, "invalid number for chunk length"
  end

  local chunk, err = self._source(len2)
  if not chunk then
    return nil, err
  end
  -- clear new line
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

---Check for trailers and add them to the headers if present
---this should only be called when chunked encoding has been detected
---@param self table
function SharedLogic.check_for_trailers(self)
  local headers, err = self:get_headers()
  if not headers then
    return nil, err
  end
  local trailer = headers:get_all("trailer")
  for _, _header_name in ipairs(trailer or {}) do
    local done, err = SharedLogic.read_header(self, "trailers")
    if done then
      break
    end
    if err ~= nil then
      return nil, err
    end
  end
  return 1
end

---
---@param self Request|Response
---@return nil|string
function SharedLogic.fill_body(self)
  if self.mode == Mode.Incoming
      and not self._received_body then
    local ty, err = SharedLogic.body_type(self)
    if not ty then
      return err
    end
    local body, err
    if ty.type == "length" then
      body, err = SharedLogic.fill_fixed_length_body(self, ty.length)
      if not body then
        return err
      end
    elseif ty.type == "close" then
      -- We only want to read until socket closing if the socket
      -- will actually close, otherwise it will hang. The lack of
      -- a content-length header is not enough of a clue as the
      -- socket may be setup for keep-alive.
      body, err = SharedLogic.fill_closed_body(self)
      if not body then
        return err
      end
    else
      body, err = SharedLogic.fill_chunked_body(self)
      SharedLogic.check_for_trailers(self)
      if not body then
        return err
      end
    end
    self.body = body
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
  if self.mode == Mode.Incoming and not self._parsed_headers then
    local err = SharedLogic.fill_headers(self)
    if err ~= nil then
      return nil, err
    end
  end
  return self.headers
end

--- Serailize the provide Request or Response into a string with new lines
---@param t Request|Response
---@return string|nil result The serialized string if nil an error occured
---@return nil|string err If not nil the error
function SharedLogic.serialize(t)
  local ret = ""
  for chunk in t:iter() do
    ret = ret .. chunk
  end
  return ret
end

---build and iterator for outbound chunked encoding
---@param self Request|Response
---@return (fun():string|nil,string|nil)|nil,nil|string
function SharedLogic.chunked_oubtbound_body_iter(self)
  local chunk_size = self._chunk_size or 1024
  local body, err = self:get_body()
  if not body then
    return nil, err
  end
  return function()
    if not body then
      return nil, "___eof___"
    end
    local chunk = string.sub(body, 1, chunk_size)
    body = string.sub(body, math.min(#chunk, chunk_size) + 1, #body)
    if chunk == "" then
      body = nil
    end
    local ret = string.format("%x\r\n%s", #chunk, chunk)
    if #chunk > 0 then
      return ret .. "\r\n"
    end
    return ret
  end
end

---build and iterator for outbound non-chunked encoding
---@param self Request|Response
---@return (fun():string|nil,string|nil)|nil,nil|string
function SharedLogic.normal_body_iter(self)
  local body, line, err
  body, err = self:get_body()
  if not body then
    return nil, err
  end
  return function()
    line, body = utils.next_line(body, true)
    if not line then
      if #body == 0 then
        return nil, "___eof___"
      else
        local ret = body
        body = ""
        return ret
      end
    end

    return line
  end
end

function SharedLogic.iter(self)
  local state = "start"
  local suffix = "\r\n"
  local header_iter = self:get_headers():iter()
  local value, body, body_iter, body_type, err, trailers_iter
  return function()
    if state == "start" then
      state = "headers"
      return self:_serialize_preamble() .. suffix
    end
    if state == "headers" then
      local header = header_iter()
      if not header then
        state = "body"
        return suffix
      end
      return header .. suffix
    end
    if state == "body" then
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
            if body_type.trailers then
              state = "trailers"
              SharedLogic.fill_headers(self, "trailers")
              if self.trailers then
                trailers_iter = self.trailers:iter()
                local trailer = trailers_iter()
                if trailer then
                  return trailer .. suffix
                end
              end
            end
            state = "complete"
            return suffix
          end
          return chunk, err
        end
        local line, err = self:_next_line()
        if err == "closed" or not line then
          state = "complete"
          return nil
        end
        return line, err
      end
      if not body_iter then
        if self._chunk_size then
          body_iter, err = SharedLogic.chunked_oubtbound_body_iter(self)
        else
          body_iter, err = SharedLogic.normal_body_iter(self)
        end
        if not body_iter then
          body_iter = function() return nil, err end
        end
      end
      value, err = body_iter()
      if not value then
        if err == "___eof___" then
          if self._chunk_size then
            if self.trailers then
              state = "trailers"
              trailers_iter = self.trailers:iter()
              return trailers_iter()
            end
            state = "complete"
            return "\r\n"
          else
            state = "complete"
          end
        else
          return nil, err
        end
      end
      return value
    end
    if state == "trailers" then
      if not trailers_iter then
        state = "complete"
        return nil
      end
      local trailer = trailers_iter()
      if not trailer then
        state = "complete"
        return "\r\n"
      end
      return trailer .. suffix
    end
  end
end

---Send the first line of the Request|Response
---@param self Request|Response
---@return integer|nil
---@return string|nil
function SharedLogic.send_preamble(self)
  if self._send_state.stage ~= "none" then
    return 1 --already sent
  end
  local line = self:_serialize_preamble() .. "\r\n"
  local s, err = utils.send_all(self.socket, line)
  if not s then
    return nil, err
  end
  self._send_state.stage = "header"
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
  local inner_headers = self.headers._inner
  while self._send_state.stage == "header" do
    local key, value = next(inner_headers, self._send_state.last_header)
    if not key then
      buf = buf .. "\r\n"

      self._send_state = {
        stage = "body",
        sent = 0,
      }
      break
    end
    local line = Headers.serialize_header(key, value) .. "\r\n"
    if #line + #buf > max then
      return buf, 0
    end
    self._send_state.last_header = key
    buf = buf .. line
  end
  local body_len = 0
  if #buf < max then
    body_len = max - #buf
    local start_idx = (self._send_state.sent or 0) + 1
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
  if self._send_state.stage == "none" then
    return self:send_preamble()
  end
  if self._send_state.stage == "body" then
    return nil, "cannot send headers after body"
  end
  local key, value = next(self.headers._inner, self._send_state.last_header)
  if not key then
    local s, e = utils.send_all(self.socket, "\r\n")
    if not s then
      return nil, e
    end
    self._send_state = {
      stage = "body",
      sent = 0,
    }
    return 1
  end
  local line = Headers.serialize_header(key, value) .. "\r\n"
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
  self._send_state.sent = (self._send_state.sent or 0) + body_len
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
  if self._send_state.stage ~= "body" and not skip_length then
    self:set_content_length(#self.body)
  end
  while self._send_state.stage ~= "body"
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
