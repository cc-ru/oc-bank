local zn = require("zn")

local module = require("oc-bank.module")
local events = module.load("events")

local STATES = {
  Hello = 1,
  KeyExchange = 2,
  Finished = 3,
  Established = 4
}

local function u64(num)
  num = num % 0xffffffffffffffff
  local result = ""
  for i = 1, 8, 1 do
    result = string.char(bit32.band(num, 0xff)) .. result
    num = bit32.rshift(num, 8)
  end
  return result
end

local states = {}


events.engine:subscribe("init", events.priority.normal, function()
  zn.connect()
end)

events.engine:subscribe("quit", events.priority.normal, function()
  zn.disconnect()
end)

event.engine:subscribe("znmsg", event.priority.normal, function()
end)

event.engine:subscribe("sendmsg", event.priority.normal, function(handler, evt)
  zn.send(evt.state.client, evt.message, evt.timeout)
end)
