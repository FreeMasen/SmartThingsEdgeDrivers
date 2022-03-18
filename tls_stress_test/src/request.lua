local ltn12 = require "ltn12"
local cosock = require "cosock"
local log = require "log"

local function request(url)
  
end

return function(i, url)
  log.debug(url, i)
  local body_t = {}
  local suc, status, headers, msg = https.request {
    url = url,
    method = 'GET',
    sink = ltn12.sink.table(body_t),
  }
  if suc then
    log.debug(i, string.format("%s %q", status, table.concat(body_t, "\n")))
  else
    log.warn(i, string.format("%q", status))
  end
end

