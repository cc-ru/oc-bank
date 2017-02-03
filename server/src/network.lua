local zn = require("zn")

local module = require("oc-bank.module")
local crypt = module.load("crypt")
local events = module.load("events")

local conns = {}

events.engine:subscribe("init", events.priority.normal, function()
  zn.connect()
end)

events.engine:subscribe("quit", events.priority.normal, function()
  zn.disconnect()
end)

event.engine:subscribe("znmsg", event.priority.normal, function(handler, evt)
  local data = evt:get()
  local conn
  for k, v in pairs(conns) do
    if v.client == data[2] then
      conn = v
      break
    end
  end
  if not conn then
    conn = crypt.newState()
    conn.client = data[2]
    table.insert(conns, conn)
  end
  local msg = conn:read(data[1])
  conn.msg = msg
  if conn.state < crypt.STATES.Established then
    crypt.handshake(conn)
  else
    events.engine:push(events.Msg {conn = conn})
  end
end)

event.engine:subscribe("sendmsg", event.priority.normal, function(handler, evt)
  zn.send(evt.state.client, evt.message, evt.timeout)
end)

return {
  conns = conns
}
