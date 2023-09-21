local zb_messages = require "st.zigbee.messages"
local zcl_messages = require "st.zigbee.zcl"
local zb_const = require "st.zigbee.constants"
local data_types = require "st.zigbee.data_types"
local read_attr_response = require "st.zigbee.zcl.global_commands.read_attribute_response"
local Level = require "st.zigbee.zcl.clusters".Level
local Status = require "st.zigbee.generated.types.ZclStatus"
local Uint8 = require "st.zigbee.data_types.Uint8"

--- The goal here is to respond to the device's `Read` message with the current
--- value of the switchLevel propery.
---
--- note: this seems to not really help with the device losing its own state
return function(device)
  local current = device:get_latest_state("main", "switchLevel", "level", 0)
  local adjusted = math.floor((255 - 2) * (current / 100)) + 2
  local response = read_attr_response.ReadAttributeResponse({
    read_attr_response.ReadAttributeResponseAttributeRecord(
      Level.attributes.CurrentLevel.ID,
      Status.SUCCESS,
      Uint8.ID,
      adjusted
    )
  })
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(read_attr_response.ReadAttributeResponse.ID)
  })
  local addrh = zb_messages.AddressHeader(
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      device:get_short_address(),
      device:get_endpoint(Level.ID),
      zb_const.HA_PROFILE_ID,
      Level.ID
  )
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = response,
  })
  local tx = zb_messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body,
  })
  device:send(tx)
end
