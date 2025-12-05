local module = {}

local offsets = {
    Vector3.new(1, 0, 0),
    Vector3.new(-1, 0, 0),
    Vector3.new(0, 0, 1),
    Vector3.new(0, 0, -1),
    Vector3.new(0, 1, 0),
    Vector3.new(0, -1, 0),
    Vector3.new(1, 0, 1),
    Vector3.new(1, 0, -1),
    Vector3.new(-1, 0, 1),
    Vector3.new(-1, 0, -1),
    Vector3.new(1, 1, 0),
    Vector3.new(-1, 1, 0),
    Vector3.new(0, 1, 1),
    Vector3.new(0, 1, -1),
    Vector3.new(1, 1, 1),
    Vector3.new(1, 1, -1),
    Vector3.new(-1, 1, 1),
    Vector3.new(-1, 1, -1)
}

function module.get(cell)
    local result = {}
    for i = 1, #offsets do
        result[i] = cell + offsets[i]
    end
    return result
end

function module.getCardinal(cell)
    local result = {}
    for i = 1, 6 do
        result[i] = cell + offsets[i]
    end
    return result
end

return module
