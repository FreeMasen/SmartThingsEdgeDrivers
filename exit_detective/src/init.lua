local Driver = require 'st.driver'
local log = require 'log'
local json = require 'dkjson'
local utils = require 'st.utils'
local capabilities = require 'st.capabilities'
local driver_lifecycle = require "driver_lifecycle"

local DRIVER_NAME = "exit-detective"

local function disco(driver, opts, cont)
  print('starting disco', cont)
end
local driver = Driver(DRIVER_NAME, {
  discovery = disco,
})

driver:register_channel_handler(driver_lifecycle(), function(driver, ch)
  local ev, err = ch:receive()
  if not ev then
    return log.error("Error receiving driver lifecycle event", err)
  end
  --- ev here is a string (currently "shutdown" is the only variant)
  log.debug("driver lifecycle event", ev)
end)
log.debug('Starting debug env Driver')
driver:run()
