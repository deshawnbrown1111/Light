local Node = import("Modules/Node")

local module = {}

function module.new()
    return {
        blocked = {}
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

function module.clear(map)
    map.blocked = {}
end

return module
