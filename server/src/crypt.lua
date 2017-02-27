local bit32 = require("bit32")
local com = require("component")

local cipher = com.advanced_cipher
local dataCard = com.data

assert(dataCard.decrypt, "Data card T2 and higher required")

local module = require("oc-bank.module")
local events = module.load("events")
local ops = module.load("ops")

local STATES = {
  Hello = 1,
  KeyExchange = 2,
  Finished = 3,
  Established = 4
}

local OPSTEPS = {
  None = 0,
  Session = 1,
  Operation = 2,
  Confirmation = 3
}

local function u64(num)
  num = num % 0xffffffffffffffff
  local lh = math.floor(num / 2^32)
  local rh = num - lh * 2^32
  local result = ""
  for i = 1, 8, 1 do
    local part = i <= 4 and lh or rh
    result = string.char(bit32.band(part, 0xff)) .. result
    num = bit32.rshift(part, 8)
  end
  return result
end

local function genSessionKey(authKey, pin)
  return dataCard.md5(authKey, pin):sub(1, 4)
end

local function genAuthKey()
  return dataCard.random(4)
end

local function genSession()
  return dataCard.random(32)
end

local function genPin()
  return dataCard.random(4)
end

local function genOpKey()
  return dataCard.random(4)
end

local function genConfirmKey(opkey, pin, operation)
  local data = opkey
  if operation.optype == ops.OPERATIONS.Transfer then
    data = data .. "transfer" .. operation.from .. operation.to ..
      u64(math.floor(operation.amount))
  elseif operation.optype == ops.OPERATIONS.Buy then
    data = data .. "buy" .. operation.from .. operation.to ..
      u64(math.floor(operation.amount))
  end
  return dataCard.md5(data, pin):sub(1, 4)
end

local function PHash(hashHmac)
  return function(secret, seed, len)
    local seedH = seed
    local result = ""
    for i = 1, math.huge, 1 do
      seedH = hashHmac(secret, seedH)
      result = result .. hashHmac(secret, seedH .. seed)
      if not len or len == #result then
        return result
      elseif len < #result then
        return result:sub(1, len)
      end
    end
  end
end

local function PRF(pHash)
  return function(secret, label, seed, len)
    return pHash(secret, label .. seed, len)
  end
end

local md5prf = PRF(PHash(function(key, data)
  return dataCard.md5(key, data)
end))

local newState
do
  local meta = {
    read = function(self, encData)
      local iv
      local encData
      if self.state >= STATES.Finished then
        iv = encData:sub(1, 16)
        encData = encData:sub(17, -1)
      end
      local decData, reason = self.decrypt(encData, self.keys.clientCipher, iv)
      if not decData then
        return nil, reason
      end
      local data = decData
      if self.state >= STATES.Finished then
        local recvMac = decData:sub(-16, -1)
        data = decData:sub(1, -17)
        local mac = self.mac(u64(seqnum.read) .. data, self.keys.clientMac)
        if mac ~= recvMac then
          return nil, "bad mac"
        end
      end
      self.seqnum.read = self.seqnum.read + 1
      return data
    end,
    write = function(self, data)
      local mac = self.mac(u64(self.seqnum.write) .. data, self.keys.serverMac)
      self.seqnum.write = self.seqnum.write + 1
      local iv = ""
      if self.state >= STATES.Finished then
        iv = dataCard.random(16)
      end
      local decData = data .. mac
      local encData = iv .. self.encrypt(data, self.keys.serverCipher, iv)
      return encData
    end,
    send = function(self, data, timeout)
      events.engine:push(events.SendMsg {
        state = self,
        message = self:write(data),
        timeout = timeout or 0
      })
    end
  }

  function newState()
    return setmetatable({
      seqnum = {
        read = 0,
        write = 0
      },
      keys = {
        serverCipher = "",
        clientCipher = "",
        serverMac = "",
        clientMac = ""
      },
      encrypt = function(data, key)
        return data
      end,
      decrypt = function(data, key)
        return data
      end,
      mac = function(data, key)
        return ""
      end,
      state = STATES.Hello,
      packets = {},
      clientRandom = "",
      serverRandom = "",
      masterSecret = "",
      msg = "",
      client = "",
      operation = {
        step = OPSTEPS.None,
        authKey = "",
        session = "",
        optype = 0
      },
      timeAlive = 0
    }, meta)
  end
end

local function handshake(state)
  local msg = state.msg
  if state.state == STATES.Hello then
    if #msg == 32 then
      state.clientRandom = msg:sub(1, 32)
      table.insert(state.packets, msg)
      state.serverRandom = dataCard.random(32)
      state:send(state.serverRandom)
      table.insert(state.packets, state.serverRandom)
      state.state = state.state + 1
    end
  elseif state.state == STATES.KeyExchange then
    local pms = cipher.decrypt(msg, config.crypt.private)
    if pms then
      local masterSecret = md5prf(pms, "master secret", state.clientRandom .. state.serverRandom, 48)
      local keys = md5prf(masterSecret, "key expansion", state.serverRandom .. state.clientRandom, 64)
      state.keys.clientMac = keys:sub(1, 16)
      state.keys.serverMac = keys:sub(17, 32)
      state.keys.clientCipher = keys:sub(33, 48)
      state.keys.serverCipher = keys:sub(49, 64)
      state.encrypt = dataCard.encrypt
      state.decrypt = dataCard.decrypt
      state.mac = dataCard.md5
      state.seqnum.write = 0
      state.seqnum.read = 0
      state.masterSecret = masterSecret
      table.insert(state.packets, msg)
      state.state = state.state + 1
    end
  elseif state.state == STATES.Finished then
    local clientFinished = md5prf(
      state.masterSecret,
      "client finished",
      dataCard.md5(table.concat(state.packets)),
      12)
    if msg == clientFinished then
      table.insert(state.packets, msg)
      local serverFinished = md5prf(
        state.masterSecret,
        "server finished",
        dataCard.md5(table.concat(state.packets)),
        12)
      state:send(serverFinished)
      state.packets = nil
      state.masterSecret = nil
      state.clientRandom = nil
      state.serverRandom = nil
      state.state = state.state + 1
    end
  end
end

return {
  handshake = handshake,
  newState = newState,
  genSession,
  genAuthKey,
  genSessionKey,
  STATES = STATES,
  u64 = u64,
  genPin = getPin,
  OPSTEPS = OPSTEPS,
  genOpKey = genOpKey,
  genConfirmKey = genConfirmKey
}
