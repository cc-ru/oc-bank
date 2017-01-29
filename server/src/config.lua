local fs = require("filesystem")

local PATH = "/etc/oc-bank.cfg"

local DEFAULT_CONFIG = [[
-- The path to the database file
db.path = "/var/db"
]]

local function existsDir(path)
  return fs.exists(path) and fs.isDirectory(path)
end

local function existsFile(path)
  return fs.exists(path) and not fs.isDirectory(path)
end

local function loadConfig()
  local base = {
    db = {}
  }

  local default = {
    db = {
      path = "/var/db"
    }
  }

  local config = {}

  local function deepCopy(value)
    if type(value) ~= "table" then
      return value
    end
    local result = {}
    for k, v in pairs(value) do
      result[k] = deepCopy(v)
    end
    return result
  end

  local function createEnv(base, default, config)
    return setmetatable({}, {
      __newindex = function(self, k, v)
        if base[k] then
          return nil
        end
        if default[k] then
          config[k] = v
        end
        return nil
      end,
      __index = function(self, k)
        if base[k] then
          config[k] = config[k] or {}
          return createEnv({}, default[k], config[k])
        end
        if default[k] then
          return config[k] or deepCopy(default[k])
        end
      end
    })
  end

  local env = createEnv(base, default, config)
  local result, reason = loadfile(PATH, "t", env)
  if not result then
    io.stderr:write("Could not load the config file! " .. tostring(reason) .. "\n")
  else
    local result, reason = pcall(result)
    if not result then
      io.stderr:write("Could not run the config file! " .. tostring(reason) .. "\n")
    end
  end

  local function setGet(base, default, config)
    return setmetatable({}, {
      __index = function(self, k)
        if base[k] then
          config[k] = config[k] or {}
          return setGet(base[k], default[k], config[k])
        elseif config[k] then
          return config[k]
        elseif default[k] then
          return default[k]
        end
      end
    })
  end

  return setGet(base, default, config)
end

local cfg = loadConfig()

if not existsFile(PATH) then
  local f, reason = io.open(PATH, "w")
  if not f then
    io.stderr:write("Failed to open config file for writing: " .. tostring(reason) .. "\n")
  else
    file:write(DEFAULT_CONFIG)
    file:close()
  end
end

return loadConfig()
