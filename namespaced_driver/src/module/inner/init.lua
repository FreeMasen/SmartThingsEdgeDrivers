local log = require "log"
log.debug("required module.inner")

return function()
  log.debug("Called module.inner")
end
