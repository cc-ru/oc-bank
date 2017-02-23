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

events.engine:subscribe("znmsg", events.priority.normal, function(handler, evt)
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
  if conn.msg == "close" then
    for k, v in pairs(conns) do
      if v == conn then
        table.remove(conns, k)
        break
      end
    end
    return
  end
  if conn.state < crypt.STATES.Established then
    crypt.handshake(conn)
  else
    events.engine:push(events.Msg {conn = conn})
  end
end)

events.engine:subscribe("conntocheck", events.priority.normal, function(handler, evt)
  for i = #conns, 1, -1 do
    local conn = conns[i]
    conn.lastMsg = conn.lastMsg + 1
    if conn.timeAlive > config.network.timeout then
      conn:send("close")
      table.remove(conns, i)
    end
  end
end)

events.engine:subscribe("sendmsg", events.priority.normal, function(handler, evt)
  zn.send(evt.state.client, evt.message, evt.timeout)
end)

events.engine:subscribe("msg", events.priority.normal, function(handler, evt)
  local conn = evt.conn
  if #conn.msg < 1 then
    return
  end
  if conn.operation.step == crypt.OPSTEPS.None then
    local result, data = pcall(srl.unserialize, conn.msg)
    if not result then
      conn:send(srl.serialize({"error", "malformed data"}))
      return
    end
    local user = data[1]
    if not ops.getUser(user) then
      conn:send(srl.serialize({"error", "no such user"}))
      return
    end
    conn.operation.authKey = crypt.genAuthKey()
    conn.operation.user = user
    conn:send(srl.serialize({"authKey", conn.operation.authKey}))
    conn.operation.step = conn.operation.step + 1
  elseif conn.operation.step == crypt.OPSTEPS.Session then
    local result, data = pcall(srl.unserialize, conn.msg)
    if not result then
      conn:send(srl.serialize({"error", "malformed data"}))
      return
    end
    if result[1] ~= "sessionKey" then
      conn:send(srl.serialize({"error", "bad packet"}))
      return
    end
    local sessionKey = crypt.genSessionKey(authKey, ops.getUser(conn.operation.user).pin)
    if sessionKey ~= result[2] then
      conn:send(srl.serialize({"error", "bad session key"}))
      conn.operation.step = crypt.OPSTEPS.None
      return
    end
    conn.operation.session = crypt.genSession()
    conn:send(srl.serialize({"session", conn.operation.session}))
    conn.operation.step = conn.operation.step + 1
  elseif conn.operation.step == crypt.OPSTEPS.Operation then
    local result, data = pcall(srl.unserialize, conn.msg)
    if not result then
      conn:send(srl.serialize({"error", "malformed data"}))
      return
    end
    if data[1] ~= "operation" then
      conn:send(srl.serialize({"error", "bad packet"}))
      return
    end
    local session = data[2]
    if conn.operation.session ~= session then
      conn:send(srl.serialize({"error", "bad session"}))
      conn.operation.step = crypt.OPSTEPS.None
      return
    end
    local operation = data[3]
    if ops.getUser(conn.operation.user).admin then
      if (operation ~= ops.OPERATIONS.NewAccount or
          operation ~= ops.OPERATIONS.Transfer or
          operation ~= ops.OPERATIONS.Buy or
          operation ~= ops.OPERATIONS.Cancel) then
        conn:send(srl.serialize({"error", "unknown operation"}))
      end
    else
      if (operation ~= ops.OPERATIONS.Transfer or
          operation ~= ops.OPERATIONS.Buy) then
        conn:send(srl.serialize({"error", "unknown operation"}))
        return
      end
    end
    if (operation == ops.OPERATIONS.Transfer or
        operation == ops.OPERATIONS.Buy) then
      local from, to, amount, comment = table.unpack(data, 4)
      if type(from) ~= "string" then
        conn:send(srl.serialize({"error", "bad packet"}))
        return
      end
      if (not ops.getUser(conn.operation.user).admin and
          conn.operation.user ~= from) then
        conn:send(srl.serialize({"error", "can't modify this account"}))
        return
      end
      if not ops.getUser(from) then
        conn:send(srl.serialize({"error", "no such user"}))
        return
      end
      if type(to) ~= "string" then
        conn:send(srl.serialize({"error", "bad packet"}))
        return
      end
      if not ops.getUser(to) then
        conn:send(srl.serialize({"error", "no such user"}))
        return
      end
      if type(amount) ~= "number" or amount < 0 then
        conn:send(srl.serialize({"error", "bad packet"}))
        return
      end
      if type(comment) ~= "string" or #comment == 0 or #comment > 512 then
        conn:send(srl.serialize({"error", "bad packet"}))
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
    elseif operation == ops.OPERATIONS.NewAccount then
      local name, isAdmin = table.unpack(data, 4)
      if type(name) ~= "string" then
        conn:send(srl.serialize({"error", "bad packet"}))
        return
      end
      if ops.getUser(name) then
        conn:send(srl.serialize({"error", "account already exists"}))
        return
      end
      if type(isAdmin) ~= "boolean" then
        conn:send(srl.serialize({"error", "bad packet"}))
        return
      end
      conn.operation.optype = operation
      conn.operation.name = name
      conn.operation.isAdmin = isAdmin
      conn.operation.opKey = crypt.genOpKey()
      conn:send(srl.serialize({"opkey", conn.operation.opKey}))
      conn.operation.step = conn.operation.step + 1
    elseif operation == ops.OPERATIONS.Cancel then
      local tid = table.unpack(data, 4)
      if type(tid) ~= "number" then
        conn:send(srl.serialize({"error", "bad packet"}))
        return
      end
      if not ops.getLine(tid) then
        conn:send(srl.serialize({"error", "unknown tid"}))
        return
      end
      conn.operation.optype = operation
      conn.operation.tid = tid
      conn.operation.opKey = crypt.genOpKey()
      conn:send(srl.serialize({"opkey", conn.operation.opKey}))
      conn.operation.step = conn.operation.step + 1
    end
  elseif conn.operation.step == crypt.OPSTEPS.Confirmation then
    local result, data = pcall(srl.unserialize, conn.msg)
    if not result then
      conn:send(srl.serialize({"error", "malformed data"}))
      return
    end
    if data[1] ~= "confirmation" then
      conn:send(srl.serialize({"error", "bad packet"}))
      return
    end
    if data[2] ~= conn.operation.session then
      conn:send(srl.serialize({"error", "bad session"}))
      conn.operation.step = crypt.OPSTEPS.None
      return
    end
    local confirmKey = crypt.genConfirmKey(
      conn.operation.opKey,
      ops.getUser(conn.operation.user).pin,
      conn.operation)
    if confirmKey ~= data[3] then
      conn:send(srl.serialize({"error", "bad confirmation key"}))
      conn.operation.step = crypt.OPSTEPS.Operation
      return
    end
    if conn.operation.optype == ops.OPERATIONS.Transfer then
      local result, id = ops.transfer(
        conn.operation.from,
        conn.operation.to,
        conn.operation.amount,
        conn.operation.comment)
      conn:send(srl.serialize({"result", result, id}))
    elseif conn.operation.optype == ops.OPERATION.Buy then
      local result, id = ops.buy(
        conn.operation.from,
        conn.operation.to,
        conn.operation.amount,
        conn.operation.comment)
      conn:send(srl.serialize({"result", result, id}))
    elseif conn.operation.optype == ops.OPERATION.NewAccount then
      local result, id = ops.newUser(
        conn.operation.name,
        conn.operation.isAdmin)
      conn:send(srl.serialize({"result", result, id}))
    elseif conn.operation.optype == ops.OPERATION.Cancel then
      local result, id = ops.cancel(conn.operation.tid)
      conn:send(srl.serialize({"result", result, id}))
    end
    conn.operation.step = crypt.OPSTEPS.Operation
  end
end)

return {
  conns = conns
}
