local Pathfinder = import("Modules/Pathfinder")
local Vector = import("Math/Vector")
local Visualizer = import("Modules/Visualizer")

local module = {}

function module.new(pathfinder, config)
    return {
        pathfinder = pathfinder,
        config = config,
        exploredPaths = {}
    }
end

function module.generateAlternativeGoals(startPos, goalPos, count)
    local alternatives = {goalPos}
    local distance = Vector.distance(startPos, goalPos)
    local offsetMagnitude = math.min(distance * 0.2, 15)
    
    for i = 1, count - 1 do
        local angle = (i / count) * math.pi * 2
        local offsetX = math.cos(angle) * offsetMagnitude
        local offsetZ = math.sin(angle) * offsetMagnitude
        
        local altGoal = goalPos + Vector3.new(offsetX, 0, offsetZ)
        table.insert(alternatives, altGoal)
    end
    
    return alternatives
end

function module.scorePath(path, goalPos, config)
    if not path or #path == 0 then return -math.huge end
    
    local score = 1000
    local totalDist = 0
    local jumps = 0
    local falls = 0
    
    for i = 1, #path - 1 do
        local current = path[i]
        local next = path[i + 1]
        
        local dist = Vector.distance(current, next)
        totalDist = totalDist + dist
        
        local heightDiff = next.Y - current.Y
        
        if heightDiff > 0.5 then
            jumps = jumps + 1
        elseif heightDiff < -2 then
            falls = falls + 1
        end
    end
    
    score = score - totalDist
    score = score - (jumps * (config.jump_penalty or 1.5) * 10)
    score = score - (falls * (config.fall_penalty or 0.8) * 5)
    
    local endDist = Vector.distance(path[#path], goalPos)
    score = score - (endDist * 2)
    
    return score
end

function module.explorePaths(explorer, startPos, goalPos, visualizer)
    local config = explorer.config
    local numPaths = config.exploration_paths or 5
    
    local alternatives = module.generateAlternativeGoals(startPos, goalPos, numPaths)
    local paths = {}
    local scores = {}
    
    for i = 1, #alternatives do
        local altGoal = alternatives[i]
        local path = Pathfinder.findPath(explorer.pathfinder, startPos, altGoal)
        
        if path then
            table.insert(paths, path)
            local score = module.scorePath(path, goalPos, config)
            table.insert(scores, score)
            
            if visualizer then
                local explorationColor = Color3.fromRGB(255, 255, 0)
                Visualizer.drawPath(visualizer, Pathfinder.cellsToWorld(explorer.pathfinder, path), 1)
                visualizer.parts[#visualizer.parts].Color = explorationColor
            end
        end
    end
    
    if #paths == 0 then return nil end
    
    local bestIdx = 1
    local bestScore = scores[1]
    
    for i = 2, #scores do
        if scores[i] > bestScore then
            bestScore = scores[i]
            bestIdx = i
        end
    end
    
    return paths[bestIdx]
end

return module
