local Node = import("Modules/Node")

local module = {}

function module.new()
    return {
        cells = {},
        blocked = {}
    }
end

function module.setBlocked(map, cell, blocked)
    local key = Node.key(cell)
    map.blocked[key] = blocked
end

function module.isBlocked(map, cell)
    local key = Node.key(cell)
    return map.blocked[key] == true
end

function module.setWalkable(map, cell)
    module.setBlocked(map, cell, false)
end

function module.scanRadius(map, origin, radius)
    local Object = import("Modules/Object")
    local Grid = import("Math/Grid")
    
    for x = -radius, radius do
        for y = -radius, radius do
            for z = -radius, radius do
                local offset = Vector3.new(x, y, z)
                local worldPos = origin + offset * 3
                local cell = Grid.toCell(worldPos, 3)
                
                local hasBlock, instance = Object.Check("down", 1)
                if hasBlock then
                    module.setBlocked(map, cell, true)
                else
                    module.setWalkable(map, cell)
                end
            end
        end
    end
end

function module.clear(map)
    map.cells = {}
    map.blocked = {}
end

return module
