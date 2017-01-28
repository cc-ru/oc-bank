local aevent = require("aevent")

local events = {}

local Engine = aevent()
events.Init = Engine:event("init")
events.Stop = Engine:event("stop")

events.engine = Engine

events.priority = {
  top = 5,
  high = 10,
  normal = 50,
  low = 75,
  bottom = 100
}

return events
