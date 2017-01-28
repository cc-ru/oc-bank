local event = require("event")

local module = require("oc-bank.module")
module.clearCache()

local events = module.load("events")

local Engine = events.Engine

local running = true

while running do
  if event.pull(.05, "interrupted") then
    running = false
  end
end

Engine:__gc()

module.clearCache()
