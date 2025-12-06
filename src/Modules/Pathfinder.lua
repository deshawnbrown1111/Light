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
        diagonalCost = opts.diagonalCost or 1.414,
        maxFallDistance = opts.maxFallDistance or 10,
        dangerPenalty = opts.dangerPenalty or 100,
        pathCache = {},
        maxCacheSize = opts.maxCacheSize or 100,
        cacheTimeout = opts.cacheTimeout or 30
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

function module.getCacheKey(startCell, goalCell)
    return Node.key(startCell) .. "->" .. Node.key(goalCell)
end

function module.getCachedPath(pathfinder, startCell, goalCell)
    local key = module.getCacheKey(startCell, goalCell)
    local cached = pathfinder.pathCache[key]
    
    if cached and (tick() - cached.time) < pathfinder.cacheTimeout then
        return cached.path
    end
    
    return nil
end

function module.cachePath(pathfinder, startCell, goalCell, path)
    local key = module.getCacheKey(startCell, goalCell)
    pathfinder.pathCache[key] = {path = path, time = tick()}
    
    local count = 0
    for _ in pairs(pathfinder.pathCache) do count = count + 1 end
    
    if count > pathfinder.maxCacheSize then
        local oldest = {key = nil, time = math.huge}
        for k, v in pairs(pathfinder.pathCache) do
            if v.time < oldest.time then
                oldest = {key = k, time = v.time}
            end
        end
        if oldest.key then
            pathfinder.pathCache[oldest.key] = nil
        end
    end
end

function module.clearCache(pathfinder)
    pathfinder.pathCache = {}
end

function module.findPath(pathfinder, startPos, goalPos)
    local startCell = Grid.toCell(startPos, pathfinder.cellSize)
    local goalCell = Grid.toCell(goalPos, pathfinder.cellSize)
    
    if Vector.distance(startCell, goalCell) < 0.1 then
        return {startCell}
    end
    
    local cached = module.getCachedPath(pathfinder, startCell, goalCell)
    if cached then
        return cached
    end
    
    local openSet = PriorityQueue.new()
    local closedSet = {}
    local gScores = {}
    
    local startH = PathCost.heuristic(startCell, goalCell)
    local startNode = Node.new(startCell, 0, startH, nil)
    
    PriorityQueue.push(openSet, startNode, startNode.f)
    gScores[Node.key(startCell)] = 0
    
    local iterations = 0
    local bestNode = startNode
    local bestDist = startH
    
    while not PriorityQueue.isEmpty(openSet) do
        iterations = iterations + 1
        if iterations > pathfinder.maxIterations then
            break
        end
        
        local current = PriorityQueue.pop(openSet)
        local currentKey = Node.key(current.cell)
        
        local distToGoal = PathCost.heuristic(current.cell, goalCell)
        if distToGoal < bestDist then
            bestDist = distToGoal
            bestNode = current
        end
        
        if Vector.distance(current.cell, goalCell) < 1.5 then
            local finalPath = module.reconstructPath(current)
            module.cachePath(pathfinder, startCell, goalCell, finalPath)
            return finalPath
        end
        
        closedSet[currentKey] = true
        
        local neighbors = pathfinder.allowDiagonal and 
            Neighbors.get(current.cell) or 
            Neighbors.getCardinal(current.cell)
        
        for i = 1, #neighbors do
            local neighborCell = neighbors[i]
            local neighborKey = Node.key(neighborCell)
            
            if not closedSet[neighborKey] and not WorldMap.isBlocked(pathfinder.map, neighborCell) then
                local currentWorld = current.cell * pathfinder.cellSize
                local neighborWorld = neighborCell * pathfinder.cellSize
                
                local isSafe, reason = WorldMap.checkPathSafe(
                    pathfinder.map, 
                    currentWorld, 
                    neighborWorld, 
                    pathfinder.maxFallDistance
                )
                
                if isSafe then
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
                    
                    if WorldMap.isDangerous(pathfinder.map, neighborCell) then
                        moveCost = moveCost + pathfinder.dangerPenalty
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
    end
    
    if bestNode and bestNode ~= startNode then
        local partialPath = module.reconstructPath(bestNode)
        return partialPath
    end
    
    return nil
end

function module.findPathAsync(pathfinder, startPos, goalPos, yieldEvery)
    yieldEvery = yieldEvery or 500
    
    local startCell = Grid.toCell(startPos, pathfinder.cellSize)
    local goalCell = Grid.toCell(goalPos, pathfinder.cellSize)
    
    if Vector.distance(startCell, goalCell) < 0.1 then
        return {startCell}
    end
    
    local cached = module.getCachedPath(pathfinder, startCell, goalCell)
    if cached then
        return cached
    end
    
    local openSet = PriorityQueue.new()
    local closedSet = {}
    local gScores = {}
    
    local startH = PathCost.heuristic(startCell, goalCell)
    local startNode = Node.new(startCell, 0, startH, nil)
    
    PriorityQueue.push(openSet, startNode, startNode.f)
    gScores[Node.key(startCell)] = 0
    
    local iterations = 0
    local bestNode = startNode
    local bestDist = startH
    
    while not PriorityQueue.isEmpty(openSet) do
        iterations = iterations + 1
        
        if iterations % yieldEvery == 0 then
            task.wait()
        end
        
        if iterations > pathfinder.maxIterations then
            break
        end
        
        local current = PriorityQueue.pop(openSet)
        local currentKey = Node.key(current.cell)
        
        local distToGoal = PathCost.heuristic(current.cell, goalCell)
        if distToGoal < bestDist then
            bestDist = distToGoal
            bestNode = current
        end
        
        if Vector.distance(current.cell, goalCell) < 1.5 then
            local finalPath = module.reconstructPath(current)
            module.cachePath(pathfinder, startCell, goalCell, finalPath)
            return finalPath
        end
        
        closedSet[currentKey] = true
        
        local neighbors = pathfinder.allowDiagonal and 
            Neighbors.get(current.cell) or 
            Neighbors.getCardinal(current.cell)
        
        for i = 1, #neighbors do
            local neighborCell = neighbors[i]
            local neighborKey = Node.key(neighborCell)
            
            if not closedSet[neighborKey] and not WorldMap.isBlocked(pathfinder.map, neighborCell) then
                local currentWorld = current.cell * pathfinder.cellSize
                local neighborWorld = neighborCell * pathfinder.cellSize
                
                local isSafe = WorldMap.checkPathSafe(
                    pathfinder.map, 
                    currentWorld, 
                    neighborWorld, 
                    pathfinder.maxFallDistance
                )
                
                if isSafe then
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
                    
                    if WorldMap.isDangerous(pathfinder.map, neighborCell) then
                        moveCost = moveCost + pathfinder.dangerPenalty
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
    end
    
    if bestNode and bestNode ~= startNode then
        local partialPath = module.reconstructPath(bestNode)
        return partialPath
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

function module.preloadPathArea(pathfinder, startPos, goalPos)
    local Grid = import("Math/Grid")
    local startCell = Grid.toCell(startPos, pathfinder.cellSize)
    local goalCell = Grid.toCell(goalPos, pathfinder.cellSize)
    
    local minX = math.min(startCell.X, goalCell.X)
    local maxX = math.max(startCell.X, goalCell.X)
    local minZ = math.min(startCell.Z, goalCell.Z)
    local maxZ = math.max(startCell.Z, goalCell.Z)
    
    local scanned = 0
    for x = minX, maxX do
        for z = minZ, maxZ do
            local cell = Vector3.new(x, startCell.Y, z)
            local worldPos = cell * pathfinder.cellSize
            WorldMap.scanCell(pathfinder.map, worldPos)
            scanned = scanned + 1
            
            if scanned % 50 == 0 then
                task.wait()
            end
        end
    end
    
    return scanned
end

return module
