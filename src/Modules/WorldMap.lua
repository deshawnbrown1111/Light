local Node = import("Modules/Node")

local module = {}

function module.new(opts)
    opts = opts or {}
    return {
        blocked = {},
        ground = {},
        heights = {},
        scanned = {},
        dangers = {},
        materials = {},
        cellSize = opts.cellSize or 3,
        scanRadius = opts.scanRadius or 100,
        maxFallCheck = opts.maxFallCheck or 20,
        debugEnabled = opts.debugEnabled or false,
        debugParts = {},
        lazyLoad = opts.lazyLoad ~= false,
        scanBudget = opts.scanBudget or 10,
        scanQueue = {},
        scanning = false
    }
end

function module.setBlocked(map, cell, isBlocked)
    local key = Node.key(cell)
    if isBlocked then
        map.blocked[key] = true
    else
        map.blocked[key] = nil
    end
end

function module.isBlocked(map, cell)
    local key = Node.key(cell)
    return map.blocked[key] == true
end

function module.setWalkable(map, cell)
    map.blocked[Node.key(cell)] = nil
end

function module.setGround(map, cell, hasGround, height, material)
    local key = Node.key(cell)
    map.ground[key] = hasGround
    if height then
        map.heights[key] = height
    end
    if material then
        map.materials[key] = material
    end
end

function module.hasGround(map, cell)
    local key = Node.key(cell)
    return map.ground[key] == true
end

function module.getHeight(map, cell)
    local key = Node.key(cell)
    return map.heights[key]
end

function module.getMaterial(map, cell)
    local key = Node.key(cell)
    return map.materials[key]
end

function module.isDangerous(map, cell)
    local key = Node.key(cell)
    return map.dangers[key] == true
end

function module.setDangerous(map, cell, isDanger)
    local key = Node.key(cell)
    map.dangers[key] = isDanger
end

function module.raycastGround(map, worldPos, maxDist)
    local workspace = game:GetService("Workspace")
    local Players = game:GetService("Players")
    
    maxDist = maxDist or map.maxFallCheck
    
    local rayOrigin = worldPos + Vector3.new(0, 2, 0)
    local rayDir = Vector3.new(0, -(maxDist + 2), 0)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local filterList = {}
    if Players.LocalPlayer and Players.LocalPlayer.Character then
        table.insert(filterList, Players.LocalPlayer.Character)
    end
    params.FilterDescendantsInstances = filterList
    
    local result = workspace:Raycast(rayOrigin, rayDir, params)
    
    return result
end

function module.scanCell(map, worldPos)
    local Grid = import("Math/Grid")
    
    local cell = Grid.toCell(worldPos, map.cellSize)
    local key = Node.key(cell)
    
    if map.scanned[key] then
        return map.ground[key] or false, map.heights[key], map.materials[key]
    end
    
    local result = module.raycastGround(map, worldPos, map.maxFallCheck)
    
    local hasGround = result ~= nil
    local height = nil
    local material = nil
    local isDanger = false
    
    if result then
        height = result.Position.Y
        material = result.Material
        
        if material == Enum.Material.Air then
            isDanger = true
        end
        
        if result.Instance then
            if result.Instance.Name:lower():find("lava") or 
               result.Instance.Name:lower():find("kill") or
               result.Instance.Name:lower():find("death") then
                isDanger = true
            end
            
            if not result.Instance.CanCollide then
                hasGround = false
            end
        end
    end
    
    map.ground[key] = hasGround
    map.heights[key] = height
    map.materials[key] = material
    map.dangers[key] = isDanger
    map.scanned[key] = true
    
    return hasGround, height, material
end

function module.scanCellLazy(map, worldPos)
    local Grid = import("Math/Grid")
    local cell = Grid.toCell(worldPos, map.cellSize)
    local key = Node.key(cell)
    
    if map.scanned[key] then
        return map.ground[key] or false, map.heights[key], map.materials[key]
    end
    
    if not map.scanQueue[key] then
        map.scanQueue[key] = worldPos
    end
    
    return nil, nil, nil
end

function module.processScanQueue(map, budget)
    if map.scanning then return 0 end
    
    map.scanning = true
    budget = budget or map.scanBudget
    local processed = 0
    
    for key, worldPos in pairs(map.scanQueue) do
        if processed >= budget then break end
        
        module.scanCell(map, worldPos)
        map.scanQueue[key] = nil
        processed = processed + 1
    end
    
    map.scanning = false
    return processed
end

function module.checkPathSafe(map, startPos, endPos, maxFallDist)
    maxFallDist = maxFallDist or 10
    local steps = math.min(math.ceil((endPos - startPos).Magnitude / 2), 5)
    
    for i = 0, steps do
        local t = i / steps
        local checkPos = startPos:Lerp(endPos, t)
        
        if map.lazyLoad then
            module.scanCellLazy(map, checkPos)
        end
        
        local result = module.raycastGround(map, checkPos, maxFallDist + 5)
        
        if not result then
            return false, "no_ground"
        end
        
        local fallDist = checkPos.Y - result.Position.Y
        if fallDist > maxFallDist then
            return false, "fall_too_high"
        end
        
        if result.Material == Enum.Material.Air then
            return false, "void"
        end
        
        if result.Instance and result.Instance.Name:lower():find("lava") then
            return false, "lava"
        end
    end
    
    return true, "safe"
end

function module.isBlockSolid(map, worldPos)
    local region = Region3.new(
        worldPos - Vector3.new(0.5, 0.5, 0.5), 
        worldPos + Vector3.new(0.5, 0.5, 0.5)
    )
    region = region:ExpandToGrid(4)
    
    local parts = workspace:FindPartsInRegion3(region, nil, 100)
    
    for _, part in ipairs(parts) do
        if part.CanCollide and not part:IsA("TrussPart") then
            return true, part
        end
    end
    
    return false, nil
end

function module.debugVisualize(map, cell, color, duration)
    if not map.debugEnabled then return end
    
    color = color or Color3.fromRGB(255, 0, 0)
    duration = duration or 5
    
    local worldPos = cell * map.cellSize
    
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(map.cellSize * 0.8, 0.5, map.cellSize * 0.8)
    part.Position = worldPos
    part.Color = color
    part.Material = Enum.Material.Neon
    part.Transparency = 0.5
    part.Parent = workspace
    
    table.insert(map.debugParts, part)
    
    task.delay(duration, function()
        if part and part.Parent then
            part:Destroy()
        end
    end)
    
    return part
end

function module.clearDebug(map)
    for _, part in ipairs(map.debugParts) do
        if part and part.Parent then
            part:Destroy()
        end
    end
    map.debugParts = {}
end

function module.clear(map)
    map.blocked = {}
    map.ground = {}
    map.heights = {}
    map.scanned = {}
    map.dangers = {}
    map.materials = {}
    map.scanQueue = {}
    module.clearDebug(map)
end

function module.getStats(map)
    local scannedCount = 0
    local groundCount = 0
    local dangerCount = 0
    local queuedCount = 0
    
    for _ in pairs(map.scanned) do scannedCount = scannedCount + 1 end
    for _ in pairs(map.ground) do groundCount = groundCount + 1 end
    for _ in pairs(map.dangers) do dangerCount = dangerCount + 1 end
    for _ in pairs(map.scanQueue) do queuedCount = queuedCount + 1 end
    
    return {
        scanned = scannedCount,
        ground = groundCount,
        dangers = dangerCount,
        queued = queuedCount
    }
end

return module
