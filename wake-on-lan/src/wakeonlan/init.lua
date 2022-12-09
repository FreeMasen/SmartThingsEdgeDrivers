local discovery = require "wakeonlan.discovery"
local log = require "log"
local socket = require "cosock".socket

local wakeonlan = {
  discovery_handler = discovery.discovery_handler,
}

local function hex_a2b(hex)
  if not hex then return "" end
  local clean = hex:gsub("[^%da-fA-F]", "")
  return clean:gsub("..", function(octet)
    return string.char(tonumber(octet:sub(1, 2), 16))
  end)
end

local function hex_b2a(bin)
  if not bin then return "" end
  return bin:gsub(".", function(byte)
    return string.format("%02x", string.byte(byte))
  end)
end

local function hex_b2a_colonize(bin)
  local hex = hex_b2a(bin)
  return hex:gsub("(..)()", function(doublet, location)
    if location > hex:len() then
      return doublet
    else
      return doublet .. ":"
    end
  end)
end

local function create_magic_packet(mac, sop)
  local mac_bin = hex_a2b(mac)
  if mac_bin:len() ~= 6 then
    err = "Invalid MAC: " .. mac
    return nil, nil, nil, err
  end

  local sop_bin = hex_a2b(sop)
  if sop and not sop_bin then
    -- A password was given but it didn't contain valid hex, probably not what
    -- was intended but also not fatal.
    log.warn("SecureOn password " .. sop .. " is not valid")
  end

  if sop_bin:len() > 6 then
    sop_bin = sop_bin:sub(1, 6)
    log.warn("SecureOn password truncated to 6 bytes")
  end

  local magic_packet = "\xFF\xFF\xFF\xFF\xFF\xFF"
  for i = 1, 16 do
    magic_packet = magic_packet .. mac_bin
  end
  magic_packet = magic_packet .. sop_bin

  return magic_packet, hex_b2a_colonize(mac_bin), hex_b2a_colonize(sop_bin)
end

function wakeonlan.send_magic_packet(mac, sop, port)
  local magic_packet, mac_hex, sop_hex, err = create_magic_packet(mac, sop)
  if not magic_packet then
    return nil, err
  end

  local port = port or 9
  local sock = socket.udp()
  assert(sock:setsockname("*", 0))
  assert(sock:setoption("broadcast", true))

  local success, err = sock:sendto(magic_packet, "255.255.255.255", port)
  if success then
    local msg = string.format("Sent WoL magic packet to %s port %d", mac_hex, port)
    if sop_hex:len() > 0 then
      msg = msg .. " pw " .. sop_hex
    end
    log.info(msg)
  else
    log.warn("Send WoL magic packet error: " .. err)
    sock:close()
    return nil, err
  end

  sock:close()
  return true
end

return wakeonlan
