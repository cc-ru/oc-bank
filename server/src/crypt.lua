local bit32 = require("bit32")
local com = require("component")

local dataCard = com.data

assert(dataCard.decrypt, "Data card T2 and higher required")

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

local function genSessionKey(authKey, pin)
  return dataCard.md5(authKey, pin):sub(1, 4)
end

local function genAuthKey()
  return dataCard.random(4)
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
      state = STATES.Hello
    }, meta)
  end
end

local function handshake(state)
  if state.state == STATES.Hello then
  elseif state.state == STATES.KeyExchange then
  elseif state.state == STATES.Finished then
  end
end
