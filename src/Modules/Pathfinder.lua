local Grid = import("Math/Grid")
local Vector = import("Math/Vector")
local PathCost = import("Math/PathCost")
local Movement = import("Math/Movement")
local Neighbors = import("Math/Neighbors")
local PriorityQueue = import("Math/PriorityQueue")
local Node = import("Modules/Node")
local WorldMap = import("Modules/WorldMap")

local module = {}

function module.new(opts)
    opts = opts or {}
    local self = {
        map = opts.map or WorldMap.new(),
        cellSize = opts.cellSize or 3,
        maxIterations = opts.maxIterations or 10000,
        allowDiagonal = opts.allowDiagonal ~= false,
        jumpCost = opts.jumpCost or 1.5,
        diagonalCost = opts.diagonalCost or 1.414
    }
    return self
end

function module.reconstructPath(node)
    local path = {}
    local current = node
    while current do
        table.insert(path, 1, current.cell)
        current = current.parent
    end
    return path
end

function module.findPath(pathfinder, startPos, goalPos)
    local startCell = Grid.toCell(startPos, pathfinder.cellSize)
    local goalCell = Grid.toCell(goalPos, pathfinder.cellSize)
    
    if Vector.distance(startCell, goalCell) < 0.1 then
        return {startCell}
    end
    
    local openSet = PriorityQueue.new()
    local closedSet = {}
    local gScores = {}
    
    local startH = PathCost.heuristic(startCell, goalCell)
    local startNode = Node.new(startCell, 0, startH, nil)
    
    PriorityQueue.push(openSet, startNode, startNode.f)
    gScores[Node.key(startCell)] = 0
    
    local iterations = 0
    
    while not PriorityQueue.isEmpty(openSet) do
        iterations = iterations + 1
        if iterations > pathfinder.maxIterations then
            return nil
        end
        
        local current = PriorityQueue.pop(openSet)
        local currentKey = Node.key(current.cell)
        
        if Vector.distance(current.cell, goalCell) < 1.5 then
            return module.reconstructPath(current)
        end
        
        closedSet[currentKey] = true
        
        local neighbors = pathfinder.allowDiagonal and Neighbors.get(current.cell) or Neighbors.getCardinal(current.cell)
        
        for i = 1, #neighbors do
            local neighborCell = neighbors[i]
            local neighborKey = Node.key(neighborCell)
            
            if not closedSet[neighborKey] and not WorldMap.isBlocked(pathfinder.map, neighborCell) then
                local offset = neighborCell - current.cell
                local isDiagonal = math.abs(offset.X) + math.abs(offset.Y) + math.abs(offset.Z) > 1
                local isJump = offset.Y > 0
                
                local moveCost = 1
                if isDiagonal then
                    moveCost = pathfinder.diagonalCost
                end
                if isJump then
                    moveCost = moveCost * pathfinder.jumpCost
                end
                
                local tentativeG = current.g + moveCost
                local neighborH = PathCost.heuristic(neighborCell, goalCell)
                
                if not gScores[neighborKey] or tentativeG < gScores[neighborKey] then
                    gScores[neighborKey] = tentativeG
                    local neighborNode = Node.new(neighborCell, tentativeG, neighborH, current)
                    PriorityQueue.push(openSet, neighborNode, neighborNode.f)
                end
            end
        end
    end
    
    return nil
end

function module.smoothPath(pathfinder, path)
    if not path or #path < 3 then return path end
    
    local smoothed = {path[1]}
    local current = 1
    
    while current < #path do
        local farthest = current + 1
        
        for i = #path, current + 1, -1 do
            local canReach = true
            local steps = math.floor(Vector.distance(path[current], path[i]) * 2)
            
            for s = 1, steps do
                local t = s / steps
                local check = Movement.lerp(path[current], path[i], t)
                local checkCell = Grid.toCell(check, pathfinder.cellSize)
                
                if WorldMap.isBlocked(pathfinder.map, checkCell) then
                    canReach = false
                    break
                end
            end
            
            if canReach then
                farthest = i
                break
            end
        end
        
        if farthest > current + 1 then
            table.insert(smoothed, path[farthest])
        else
            table.insert(smoothed, path[current + 1])
        end
        
        current = farthest
    end
    
    if smoothed[#smoothed] ~= path[#path] then
        table.insert(smoothed, path[#path])
    end
    
    return smoothed
end

function module.cellsToWorld(pathfinder, cells)
    local world = {}
    for i = 1, #cells do
        local cell = cells[i]
        local worldPos = cell * pathfinder.cellSize
        table.insert(world, worldPos)
    end
    return world
end

function module.findAndSmooth(pathfinder, startPos, goalPos)
    local cellPath = module.findPath(pathfinder, startPos, goalPos)
    if not cellPath then return nil end
    
    local smoothedCells = module.smoothPath(pathfinder, cellPath)
    local worldPath = module.cellsToWorld(pathfinder, smoothedCells)
    
    return worldPath
end

return module
