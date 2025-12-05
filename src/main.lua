local prints = {}

local function log(...)
    local msg = table.concat({...}, " ")
    table.insert(prints, msg)
    print(msg)
end

local function logErr(...)
    local msg = "[ERROR] " .. table.concat({...}, " ")
    table.insert(prints, msg)
    warn(msg)
end

local success, err = pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/deshawnbrown1111/Light/refs/heads/main/src/init.lua"))()
    log("Init loaded successfully")
end)

if not success then
    logErr("Failed to load init:", err)
    return
end

local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

local Pathfinder, Controller, WorldMap

success, err = pcall(function()
    Pathfinder = import("Modules/Pathfinder")
    Controller = import("Modules/Controller")
    WorldMap = import("Modules/WorldMap")
    log("Modules imported successfully")
end)

if not success then
    logErr("Failed to import modules:", err)
    return
end

local map = WorldMap.new()
local pathfinder = Pathfinder.new({map = map})
local controller = Controller.new({
    stuckThreshold = 5
})

controller.onComplete = function()
    log("Reached goal!")
end

controller.onStuck = function()
    log("Bot got stuck!")
end

local startPos = hrp.Position
local goalPos = hrp.Position + Vector3.new(50, 0, 50)

log("Starting pathfinding from", tostring(startPos), "to", tostring(goalPos))

local path
success, err = pcall(function()
    path = Pathfinder.findAndSmooth(pathfinder, startPos, goalPos)
end)

if not success then
    logErr("Pathfinding failed:", err)
    return
end

if path then
    log("Path found with", #path, "waypoints")
    
    success, err = pcall(function()
        Controller.setPath(controller, path)
        Controller.start(controller)
    end)
    
    if not success then
        logErr("Failed to start controller:", err)
        return
    end
    
    log("Controller started, bot is moving!")
else
    logErr("No path found!")
end

wait(2)

local output = table.concat(prints, "\n")
setclipboard(output)
log("=== OUTPUT COPIED TO CLIPBOARD ===")
