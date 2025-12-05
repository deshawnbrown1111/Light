local import = loadstring(game:HttpGet("https://raw.githubusercontent.com/deshawnbrown1111/Light/refs/heads/main/src/init.lua"))()

local Pathfinder = import("Modules/Pathfinder")
local Controller = import("Modules/Controller")
local WorldMap = import("Modules/WorldMap")

local map = WorldMap.new()
local pathfinder = Pathfinder.new({map = map})
local controller = Controller.new()

controller.onComplete = function()
    print("Reached goal!")
end

controller.onStuck = function()
    print("Bot got stuck!")
end

local path = Pathfinder.findAndSmooth(pathfinder, startPos, goalPos)
if path then
    Controller.setPath(controller, path)
    Controller.start(controller)
end
