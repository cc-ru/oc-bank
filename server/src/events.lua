local aevent = require("aevent")

local events = {}

local Engine = aevent()
events.Init = Engine:event("init")
events.Stop = Engine:event("stop")
events.ZnMsg = Engine:event("znmsg")
events.SendMsg = Engine:event("sendmsg")
events.Msg = Engine:event("msg")
events.ConnTOCheck = Engine:event("conntocheck")

Engine:stdEvent("zn_message", events.ZnMsg)

Engine:timer(1, events.ConnTOCheck, math.huge)

events.engine = Engine

events.priority = {
  top = 5,
  high = 10,
  normal = 50,
  low = 75,
  bottom = 100
}

return events
