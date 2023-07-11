---@class OutboundBuffer
---@field contents string
local OutboundBuffer = {}
OutboundBuffer.__index = OutboundBuffer

function OutboundBuffer.new(contents)
  return setmetatable({
    contents = contents,
  }, OutboundBuffer)
end

function OutboundBuffer:append(contents)
  self.contents = self.contents .. contents
end

function OutboundBuffer:__call(length)
  if #self.contents == 0 then
    return nil
  end
  if length == 0 then
    return ""
  end
  local ret = string.sub(self.contents, 1, length)
  self.contents = string.sub(self.contents, length+1)
  return ret
end

return OutboundBuffer
