local serialization = require("serialization")

local module = require("oc-bank.module")

local config = module.load("config")

local function loadDB()
  local f = io.open(config.db.path, "r")
  local content = f:read("*a")
  f:close()
  return serialization.unserialize(content)
end

local function saveDB(db)
  local content = serialization.serialize(db)
  local f = io.open(config.db.path, "w")
  f:write(content)
  f:close()
end

local mod = {}
mod.db = loadDB()
mod.save = function()
  saveDB(mod.db)
end

return mod
