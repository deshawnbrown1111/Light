local Node = import("Modules/Node")
local Object = import("Modules/Object")

local module = {}

function module.new()
    return {
        blocked = {},
        ground = {},
        scanned = {}
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

function module.setGround(map, cell, hasGround)
    local key = Node.key(cell)
    map.ground[key] = hasGround
end

function module.hasGround(map, cell)
    local key = Node.key(cell)
    return map.ground[key] == true
end

function module.scanCell(map, worldPos)
    local workspace = game:GetService("Workspace")
    local Grid = import("Math/Grid")
    
    local cell = Grid.toCell(worldPos, 3)
    local key = Node.key(cell)
    
    if map.scanned[key] then
        return map.ground[key] or false
    end
    
    local rayOrigin = worldPos + Vector3.new(0, 1, 0)
    local rayDir = Vector3.new(0, -10, 0)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {game:GetService("Players").LocalPlayer.Character}
    
    local result = workspace:Raycast(rayOrigin, rayDir, params)
    
    local hasGround = result ~= nil
    map.ground[key] = hasGround
    map.scanned[key] = true
    
    return hasGround
end

function module.clear(map)
    map.blocked = {}
    map.ground = {}
    map.scanned = {}
end

return module
