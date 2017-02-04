local srl = require("serialization")
local zn = require("zn")

local module = require("oc-bank.module")
local crypt = module.load("crypt")
local events = module.load("events")
local ops = module.load("ops")

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

event.engine:subscribe("msg", event.priority.normal, function(handler, evt)
  local conn = evt.conn
  if #conn.msg < 1 then
    return
  end
  if conn.operation.step == crypt.OPSTEPS.None then
    local result, data = pcall(srl.unserialize, conn.msg)
    if not result then
      -- TODO: report an error
      return
    end
    local user = data[1]
    if not ops.getUser(user) then
      -- TODO: report an error
      return
    end
    conn.operation.authKey = crypt.genAuthKey()
    conn.operation.user = user
    conn:send(srl.serialize({"authKey", conn.operation.authKey}))
    conn.operation.step = conn.operation.step + 1
  elseif conn.operation.step == crypt.OPSTEPS.Session then
    local result, data = pcall(srl.unserialize, conn.msg)
    if not result then
      -- TODO: report an error
      return
    end
    if result[1] ~= "sessionKey" then
      -- TODO: report an error
      return
    end
    local sessionKey = crypt.genSessionKey(authKey, ops.getUser(conn.operation.user).pin)
    if sessionKey ~= result[2] then
      -- TODO: report an error
      return
    end
    conn.operation.session = crypt.genSession()
    conn:send(srl.serialize({"session", conn.operation.session}))
    conn.operation.step = conn.opeartion.step + 1
  elseif conn.operation.step == crypt.OPSTEPS.Operation then
    local result, data = pcall(srl.unserialize, conn.msg)
    if not result then
      -- TODO: report an error
      return
    end
    if data[1] ~= "operation" then
      -- TODO: report an error
      return
    end
    local session = data[2]
    if conn.operation.session ~= session then
      -- TODO: report an error
      return
    end
    local operation = data[3]
    if not ops.OPERATIONS[operation] then
      -- TODO: report an error
      return
    end
    if (operation == ops.OPERATIONS.Transfer or
        operation == ops.OPERATIONS.Buy) then
      local from, to, amount, comment = table.unpack(data, 4)
      if not from or not ops.getUser(from) then
        -- TODO: report an error
        return
      end
      if not to or not ops.getUser(to) then
        -- TODO: report an error
        return
      end
      if type(amount) ~= "number" or amount < 0 then
        -- TODO: report an error
        return
      end
      if type(comment) ~= "string" then
        -- TODO: report an error
        return
      end
      conn.operation.optype = operation
      conn.operation.from = from
      conn.operation.to = to
      conn.operation.amount = amount
      conn.operation.comment = comment
      conn.operation.opKey = crypt.genOpKey()
      conn:send(srl.serialize({"opkey", conn.operation.opKey}))
      conn.operation.step = conn.operation.step + 1
    else
      -- TODO: report an error
      return
    end
  elseif conn.operation.step == crypt.OPSTEPS.Confirmation then
    local result, data = pcall(srl.unserialize, conn.msg)
    if not result then
      -- TODO: report an error
      return
    end
    if data[1] ~= "confirmation" then
      -- TODO: report an error
      return
    end
    if data[2] ~= conn.operation.session then
      -- TODO: report an error
      return
    end
    local confirmKey = crypt.genConfirmKey(
      conn.operation.opKey,
      ops.getUser(conn.operation.user).pin,
      conn.operation)
    if confirmKey ~= data[3] then
      -- TODO: report an error
      return
    end
    if conn.operation.optype == ops.OPERATIONS.Transfer then
      local result, id = ops.transfer(
        conn.operation.from,
        conn.operation.to,
        conn.operation.amount,
        conn.operation.comment)
      conn:send(srl.serialize({"result", result}))
    elseif conn.operation.optype == ops.OPERATION.Buy then
      local result, id = ops.buy(
        conn.operation.from,
        conn.operation.to,
        conn.operation.amount,
        conn.operation.comment)
      conn:send(srl.serialize({"result", result}))
    end
    conn.operation.step = crypt.OPSTEPS.Operation
  end
end)

return {
  conns = conns
}
