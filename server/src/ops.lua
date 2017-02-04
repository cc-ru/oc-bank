local module = require("oc-bank.module")
local crypt = module.load("crypt")
local db = module.load("db")

local OPERATIONS = {
  NewAccount = 1,
  Transfer = 2,
  Buy = 3,
  Cancel = 4
}

local function len(tbl)
  local result = 0
  for _ in pairs(tbl) do
    result = result + 1
  end
  return result
end

local function datetime()
  -- TODO: implement
end

local function getUser(name)
  for k, v in pairs(db.db.users) do
    if v.name == name then
      return v, k
    end
  end
  return false
end

local function getLine(id)
  for k, v in pairs(db.db.log) do
    if v.id == id then
      return v
    end
  end
  return false
end

local function log(data)
  local line
  if data.optype == OPERATIONS.NewAccount then
    line = {
      optype = OPERATIONS.NewAccount,
      name = data.name
    }
  elseif data.optype == OPERATIONS.Transfer then
    line = {
      optype = OPERATIONS.Transfer,
      from = data.from,
      to = data.to,
      amount = data.amount,
      comment = data.comment
    }
  elseif data.optype == OPERATIONS.Buy then
    line = {
      optype = OPERATIONS.Buy,
      from = data.from,
      to = data.from,
      amount = data.amount,
      comment = data.amount
    }
  end
  if not line then
    return false
  end
  line.timestamp = datetime()
  line.id = len(db.db.log) + 1
  line.cancelled = false
  table.insert(db.db.log, line)
  return line
end

local function newUser(name)
  if getUser(name) then
    return false
  end
  local user = {
    name = name,
    pin = crypt.genPin(),
    balance = 0
  }
  table.insert(db.db.users, user)
  local id = log {optype = OPERATIONS.NewAccount,
                  name = name}
  db.save()
  return true, id
end

local function transfer(from, to, amount, comment)
  local fromAccount = getUser(from)
  local toAccount = getUser(to)
  if not (fromAccount and toAccount) then
    return false
  end
  if fromAccount.balance < amount then
    return false
  end
  if amount < 0 then
    return false
  end
  fromAccount.balance = fromAccount.balance - amount
  toAccount.balance = toAccount.balance + amount
  local id = log {optype = OPERATIONS.Transfer,
                  from = from,
                  to = to,
                  amount = amount,
                  comment = comment}
  db.save()
  return true, id
end

local function buy(from, to, amount, comment)
  local fromAccount = getUser(from)
  local toAccount = getUser(to)
  if not (fromAccount and toAccount) then
    return false
  end
  if fromAccount.balance < amount then
    return false
  end
  if amount < 0 then
    return false
  end
  fromAccount.balance = fromAccount.balance - amount
  toAccount.balance = toAccount.balance + amount
  local id = log {optype = OPERATIONS.Buy,
                  from = from,
                  to = to,
                  amount = amount,
                  comment = comment}
  db.save()
  return true, id
end

local function cancel(tid)
  local line = getLine(tid)
  if not line then
    return false
  end
  if line.optype == OPERATIONS.NewAccount then
    local _, k = getUser(line.name)
    table.remove(db.db.users, k)
  elseif line.optype == OPERATIONS.Transfer then
    local fromAccount = getUser(line.from)
    local toAccount = getUser(line.to)
    if fromAccount then
      fromAccount.balance = fromAccount.balance + line.amount
    end
    if toAccount then
      toAccount.balance = toAccount.balance - line.amount
    end
  elseif line.optype == OPERATIONS.Buy then
    local fromAccount = getUser(line.from)
    local toAccount = getUser(line.to)
    if fromAccount then
      fromAccount.balance = fromAccount.balance + line.amount
    end
    if toAccount then
      toAccount.balance = toAccount.balance - line.amount
    end
  elseif line.optype == OPERATIONS.Cancel then
    local operation = getLine(line.id)
    if operation.optype == OPERATIONS.NewAccount then
      -- nothing can be done
      return false
    elseif operation.optype == OPERATIONS.Transfer then
      local fromAccount = getUser(operation.from)
      local toAccount = getUser(operation.to)
      if fromAccount then
        fromAccount.balance = fromAccount.balance - line.amount
      end
      if toAccount then
        toAccount.balance = toAccount.balance + line.amount
      end
      operation.cancelled = false
    elseif operation.optype == OPERATIONS.Buy then
      local fromAccount = getUser(operation.from)
      local toAccount = getUser(operation.to)
      if fromAccount then
        fromAccount.balance = fromAccount.balance - line.amount
      end
      if toAccount then
        toAccount.balance = toAccount.balance + line.amount
      end
      operation.cancelled = false
    elseif operation.optype == OPERATIONS.Cancel then
      -- it can be cancelled directly
      return false
    end
  end
  line.cancelled = true
  local id = log {optype = OPERATIONS.Cancel,
                  id = tid}
  db.save()
  return true, id
end

return {
  newUser = newUser,
  transfer = transfer,
  buy = buy,
  cancel = cancel
}
