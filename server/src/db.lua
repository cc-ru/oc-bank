local fs = require("filesystem")
local serialization = require("serialization")

local module = require("oc-bank.module")

local config = module.load("config")

local function loadDB()
  if not fs.exists(fs.path(config.db.path)) then
    fs.makeDirectory(fs.path(config.db.path))
  end
  if not fs.exists(config.db.path) then
    local f = io.open(config.db.path, "w")
    f:write("{}")
    f:close()
  end
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

if not mod.db.users or not mod.db.log then
  mod.db = {users = {}, log = {}}
  mod.save()
end

return mod
