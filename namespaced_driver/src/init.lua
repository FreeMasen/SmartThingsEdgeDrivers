local Driver = require 'st.driver'
local target = require "module.inner"

local DRIVER_NAME = "namespaced-driver"

local function disco(driver, opts, cont)
  print('starting disco', cont)
end
local driver = Driver(DRIVER_NAME, {
  discovery = disco,
})

target()

driver:run()
