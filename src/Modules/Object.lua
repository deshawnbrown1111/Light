-- // NOT USED AS OF RN

local Players = game:GetService("Players")
local plr = Players.LocalPlayer

local module = {}

local dirs = {
    front = Vector3.new(0,0,-1),
    back = Vector3.new(0,0,1),
    left = Vector3.new(-1,0,0),
    right = Vector3.new(1,0,0),
    up = Vector3.new(0,1,0),
    down = Vector3.new(0,-1,0)
}

function module.Check(dir, dist)
    dir = string.lower(dir)
    dist = dist or 5
    local char = plr.Character or plr.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart")
    local lookCF = hrp.CFrame
    local baseDir = dirs[dir]
    if not baseDir then return false end
    local worldDir = (lookCF:VectorToWorldSpace(baseDir)) * dist
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local result = workspace:Raycast(hrp.Position, worldDir, params)
    if result and result.Instance then
        return true, result.Instance
    end
    return false, nil
end

function module.RaycastWorld(origin, direction, distance, filterList)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = filterList or {plr.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local result = workspace:Raycast(origin, direction * distance, params)
    return result
end

function module.HasGroundBelow(position, maxDist)
    maxDist = maxDist or 10
    local rayOrigin = position + Vector3.new(0, 1, 0)
    local rayDir = Vector3.new(0, -1, 0)
    local result = module.RaycastWorld(rayOrigin, rayDir, maxDist + 1)
    return result ~= nil, result
end

function module.GetGroundHeight(position, maxDist)
    local hasGround, result = module.HasGroundBelow(position, maxDist)
    if hasGround and result then
        return result.Position.Y
    end
    return nil
end

function module.IsPathSafe(startPos, endPos, maxFallDist)
    maxFallDist = maxFallDist or 10
    local steps = math.ceil((endPos - startPos).Magnitude / 2)
    
    for i = 0, steps do
        local t = i / steps
        local checkPos = startPos:Lerp(endPos, t)
        local hasGround, result = module.HasGroundBelow(checkPos, maxFallDist)
        
        if not hasGround then
            return false
        end
        
        if result then
            local fallDist = checkPos.Y - result.Position.Y
            if fallDist > maxFallDist then
                return false
            end
        end
    end
    
    return true
end

function module.IsBlockSolid(position)
    local region = Region3.new(position - Vector3.new(0.5, 0.5, 0.5), position + Vector3.new(0.5, 0.5, 0.5))
    region = region:ExpandToGrid(4)
    local parts = workspace:FindPartsInRegion3(region, nil, 100)
    
    for _, part in ipairs(parts) do
        if part.CanCollide and not part:IsA("TrussPart") then
            return true, part
        end
    end
    
    return false, nil
end

function module.ScanArea(center, radius, heightCheck)
    heightCheck = heightCheck or 10
    local results = {}
    
    for x = -radius, radius, 3 do
        for z = -radius, radius, 3 do
            local checkPos = center + Vector3.new(x, 0, z)
            local hasGround, result = module.HasGroundBelow(checkPos, heightCheck)
            
            table.insert(results, {
                position = checkPos,
                hasGround = hasGround,
                groundHeight = result and result.Position.Y or nil
            })
        end
    end
    
    return results
end

return module
