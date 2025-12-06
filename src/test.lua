getgenv().__import_cache = nil

local import = loadstring(game:HttpGet("https://raw.githubusercontent.com/deshawnbrown1111/Light/refs/heads/main/src/init.lua"))()

local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local hrp = char:WaitForChild("HumanoidRootPart")

local Pathfinder = import("Modules/Pathfinder")
local Controller = import("Modules/Controller")
local WorldMap = import("Modules/WorldMap")
local Goals = import("Modules/Goals")
local Visualizer = import("Modules/Visualizer")
local Config = import("Modules/Config")
local PathExplorer = import("Modules/PathExplorer")

local config = Config.new()
Config.set(config, "walk_when_air", false)
Config.set(config, "exploration_paths", 7)

local map = WorldMap.new()
local pathfinder = Pathfinder.new({map = map, cellSize = config.cell_size})
local visualizer = Visualizer.new()
local explorer = PathExplorer.new(pathfinder, config)

local targetPos = hrp.Position + hrp.CFrame.LookVector * 100

print("Exploring paths...")
local bestPath = PathExplorer.explorePaths(explorer, hrp.Position, targetPos, visualizer)

if bestPath then
    print("Best path found! Waiting", config.exploration_visualize_time, "seconds...")
    wait(config.exploration_visualize_time)
    
    Visualizer.clear(visualizer)
    
    local worldPath = Pathfinder.cellsToWorld(pathfinder, bestPath)
    local smoothedPath = Pathfinder.smoothPath(pathfinder, bestPath)
    local finalPath = Pathfinder.cellsToWorld(pathfinder, smoothedPath)
    
    local controller = Controller.new({
        stuckThreshold = 5,
        visualizer = visualizer
    })
    
    Controller.setPath(controller, finalPath)
    Controller.start(controller)
    
    print("Moving!")
else
    warn("No path found!")
end
