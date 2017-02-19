local event = require("event")

local module = require("oc-bank.module")
module.clearCache()

local events = module.load("events")

local engine = events.engine

module.load("config")
module.load("db")
module.load("ops")
module.load("crypt")
module.load("network")

local running = true

while running do
  if event.pull(.05, "interrupted") then
    running = false
  end
end

engine:__gc()

module.clearCache()
