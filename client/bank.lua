local com = require("component")
local event = require("event")

local cipher = com.advanced_cipher
local dataCard = com.data
local modem = com.modem

if not dataCard.random then
  -- yell at user if trying to run without data card T2/T3
  error("data card of at least t2 required")
end

local bank = {}

local publicKey
local serverAddr

local connected = false

local STATES = {
  Hello = 1,
  KeyExchange = 2,
  Finished = 3,
  Established = 4
}

local function u64(num)
  num = num % 0xffffffffffffffff
  local lh = math.floor(num / 0xffffffff)
  local rh = num - lh * 0xffffffff
  local result = ""
  for i = 1, 8, 1 do
    local part = i <= 4 and lh or rh
    result = string.char(bit32.band(part, 0xff)) .. result
    num = bit32.rshift(part, 8)
  end
  return result
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

local function newConn()
  local conn = {
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
    msg = ""
  }

  setmetatable(conn, {
    __index = {
      read = function(self, encData)
        local iv = encData
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
          local mac = self.mac(u64(seqnum.read) .. data, self.keys.serverMac)
          if mac ~= recvMac then
            return nil, "bad mac"
          end
        end
        self.seqnum.read = self.seqnum.read + 1
        return data
      end,
      write = function(self, data)
        local mac = self.mac(u64(self.seqnum.write) .. data, self.keys.clientMac)
        self.seqnum.write = self.seqnum.write + 1
        local iv = ""
        if self.state >= STATES.Finished then
          iv = dataCard.random(16)
        end
        local decData = data .. mac
        local encData = iv .. self.encrypt(data, self.keys.clientCipher, iv)
        return encData
      end,
      send = function(self, data, save)
        local msg = self:write(data)
        zn.send(serverAddr, msg)
        if save then
          table.insert(self.packets, msg)
        end
      end,
      recv = function(self, save)
        -- TODO
        if save then
          table.insert(self.packets, msg)
        end
        return msg
      end
    }
  })

  return conn
end

function bank.init(key, address)
  checkArg(1, key, "table")
  checkArg(1, address, "string")
  publicKey = key
  serverAddr = address
end

function bank.connect()
  if connected then
    return false
  end
  local conn = newConn()
  conn.clientRandom = dataCard.random(32)
  conn:send(conn.clientRandom, true)
  conn.serverRandom = conn:recv(true)
  conn.state = conn.state + 1

  local pms = dataCard.random(48)
  conn:send(cipher.encrypt(pms, publicKey), true)
  conn.masterSecret = md5prf(pms, "master secret", conn.clientRandom .. conn.serverRandom, 48)
  local keys = md5prf(masterSecret, "key expansion", conn.serverRandom .. conn.clientRandom, 64)
  conn.keys.clientMac = keys:sub(1, 16)
  conn.keys.serverMac = keys:sub(17, 32)
  conn.keys.clientCipher = keys:sub(33, 48)
  conn.keys.serverCipher = keys:sub(49, 64)
  conn.encrypt = dataCard.encrypt
  conn.decrypt = dataCard.decrypt
  conn.mac = dataCard.md5
  conn.seqnum.write = 0
  conn.seqnum.read = 0
  conn.state = conn.state + 1

  local clientFinished = md5prf(state.masterSecret,
                                "client finished",
                                dataCard.md5(table.concat(state.packets)),
                                12)
  conn:send(clientFinished, true)
  local recvFinished = conn:recv()
  local serverFinished = md5prf(state.masterSecret,
                                "server finished",
                                dataCard.md5(table.concat(state.packets)),
                                12)
  if recvFinished ~= serverFinished then
    conn = newConn()
    return false
  end
  conn.packets = nil
  conn.masterSecret = nil
  conn.clientRandom = nil
  conn.serverRandom = nil
  conn.state = conn.state + 1

  return true
end

function bank.disconnect()
  if not connected then
    return false
  end
  conn:send("close")
  conn = newConn()
  return true
end
