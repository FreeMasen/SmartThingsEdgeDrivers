local log = require 'log'
local cosock = require 'cosock'
local MULTIADDR = '239.255.255.250'
local MULTIPORT = 1900

local SERVER_HEADER = 'Server: SmartThings/* UPnP/1.0 DreamPresence/1.0'
local CACHE_CONTROL = 'Cache-Control: max-age=900'

local function listen_for_ssdp_search(driver, sock)
  driver:register_channel_handler(sock, function(driver)
    log.debug('recieving message from muticast addr')
    local bytes, ip, port = assert(sock:receivefrom())
    if not string.find(bytes, '^M%-SEARCH') then
      log.debug('Not M-SEARCH')
      return
    end
    local _, _, st = string.find(bytes, 'ST: ?([^\r\n ]+)\r\n')
    if not st then
      log.debug('No ST found')
      return
    end
    if not (st == 'ssdp:all'
    or st == 'ssdp:rootdevice'
    or st ~= string.format('uuid:%s', driver.server.uuid)) then
        log.debug(st, 'not our target')
        return
    end
    log.debug('sending reply to', ip, port)
    local reply = cosock.socket.udp()
    reply:sendto(table.concat({
      'HTTP/1.1 200 Ok',
      CACHE_CONTROL,
      'EXT',
      string.format('LOCATION: http://%s:%s/discovery', driver.server:get_ip(), driver.server.port),
      SERVER_HEADER,
      string.format('ST: %s', st),
      string.format('USN: uuid:%s::upnp:rootdevice', driver.server.uuid),
      '\r\n',
    },'\r\n'), ip, port)
  end)
end

local function send_upnp_advert(sock, ip, port, server_id)
  assert(sock, "no socket on send")
  log.debug('Building message')
  local msg = table.concat({
    'NOTIFY * HTTP/1.1',
    SERVER_HEADER,
    CACHE_CONTROL,
    string.format('Location: http://%s:%s/discovery', ip, port),
    'NTS: ssdp:alive',
    'NT: upnp:rootdevice',
    string.format('USN: uuid:%s::upnp:rootdevice', server_id),
    string.format('Host: %s:%s', ip, port),
    '\r\n'
  }, '\r\n')
  log.debug(string.format('sending %q', msg))
  assert(sock:sendto(msg, MULTIADDR, MULTIPORT))
  log.debug('message sent')
end

return function(driver)
  while not (driver.server or driver.server.get_ip()) do
    log.debug('not yet ready, sleeping')
    cosock.socket.sleep(1)
  end
  local sock = assert(cosock.socket.udp())
  assert(sock:setoption('reuseaddr', true))
  assert(sock:setsockname(MULTIADDR, MULTIPORT))
  assert(sock:setoption('ip-add-membership', {multiaddr = MULTIADDR, interface = '0.0.0.0'}))
  assert(sock:setoption('ip-multicast-loop', false))
  listen_for_ssdp_search(driver, sock)
  driver:call_on_schedule(5, function()
    local s, err = pcall(send_upnp_advert, sock, driver.server:get_ip(), driver.server.port, driver.server.uuid)
    if not s then
      log.error("failed to send upnp advert", err)
    end
  end)
end