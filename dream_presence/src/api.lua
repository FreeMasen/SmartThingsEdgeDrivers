local ltn12 = require 'ltn12'
local https = require 'https'
local json = require 'dkjson'
local socket = require 'socket'
local log = require 'log'


local function login(ip, username, password)
  log.trace('login', ip, username)
  local body_t = {
    username = username,
    password = password,
    rememberMe = true,
  }
  local body = json.encode(body_t)
  local rep_t = {}
  local url = string.format('https://%s/api/auth/login', ip)
  local suc, status, headers, msg = https.request {
    url = url,
    method = 'POST',
    headers = {
      ['Content-Type'] = 'application/json',
      ['Content-Length'] = #body,
    },
    source = ltn12.source.string(body),
    sink = ltn12.sink.table(rep_t),
  }
  log.debug(string.format("response %s %s %q %s", suc, status, headers and "<headers>", msg))
  if not suc then
    return nil, string.format('%s %s', status, msg)
  end
  if status ~= 200 then
    return nil, string.format('Invalid status %s\n%s', msg, table.concat(rep_t))
  end
  local cookie = headers['set-cookie']
  if not cookie then
    log.error("No cookie in response")
    return nil, 'no cookie in response'
  end
  local xsrf = headers['x-csrf-token']
  if not xsrf then
    log.error("No xsrf token in response")
    return nil, 'no X-CSRF-Token'
  end
  log.debug("Successfully logged in")
  return cookie, xsrf
end

local function get_sites(ip, cookie, xsrf)
  log.trace("get_sites")
  local body_t = {}
  local url = string.format('https://%s/proxy/network/api/s/default/stat/sta', ip)
  local suc, status, headers, msg = https.request {
    url = url,
    method = 'GET',
    sink = ltn12.sink.table(body_t),
    headers = {
      ['Accept'] = 'application/json',
      ['Cookie'] = cookie,
      ['X-CSRF-Token'] = xsrf,
    }
  }
  log.debug(string.format("reply: %s %q %s %q", suc, status, headers and "<headers>", msg))
  if not suc then
    log.error("Error getting sites", status)
    return nil, status
  end
  if status ~= 200 then
    log.error("Non 200 error code: ", status, msg)
    return nil, string.format('Error in reply %s\n%s', msg, table.concat(body_t))
  end
  log.debug("Got sites")
  local json_text = table.concat(body_t)
  local t, idx, err = json.decode(json_text)
  if not t then
    return nil, string.format("Error decoding json: %s\n", err or idx, json_text)
  end
  return t
end

local function check_for_presence(ip, device_name, cookie, xsrf, ct)
  local sites, err = get_sites(ip, cookie, xsrf)
  if not sites then
    log.error("failed to complete request:", err)
    return nil, err
  end
  for _, client in ipairs(sites.data) do
    if client.hostname == device_name then
      local now = socket.gettime()
      local diff = now - client.last_seen
      return diff < 60
    end
  end
  return false
end

return {
  check_for_presence = check_for_presence,
  login = login,
  get_sites = get_sites,
}
