local ltn12 = require 'ltn12'
local https = require 'ssl.https'
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

  if not suc then
    return nil, string.format('%s %s', status, msg)
  end
  if status ~= 200 then
    return nil, string.format('Invalid status %s\n%s', msg, table.concat(rep_t))
  end
  local cookie = headers['set-cookie']
  if not cookie then
    return nil, 'no cookie in response'
  end
  local xsrf = headers['x-csrf-token']
  if not xsrf then
    return nil, 'no X-CSRF-Token'
  end
  return cookie, xsrf
end

local function get_sites(ip, cookie, xsrf)
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
  if not suc then
    return nil, status
  end
  if status ~= 200 then
    return nil, string.format('Error in reply %s\n%s', msg, table.concat(body_t))
  end
  return json.decode(table.concat(body_t))
end

local function check_for_presence(ip, device_name, cookie, xsrf)
  local sites, err = get_sites(ip, cookie, xsrf)
  if not sites then
    error(err)
  end
  print('sites', json.encode(sites))
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
  login = login
}
