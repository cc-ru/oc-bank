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
  -- TODO
end

function bank.disconnect()
  if not connected then
    return false
  end
  -- TODO
end
