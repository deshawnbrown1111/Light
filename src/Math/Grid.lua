local module = {}

function module.snap(v, size)
    size = size or 1
    return Vector3.new(
        math.floor(v.X/size+0.5)*size,
        math.floor(v.Y/size+0.5)*size,
        math.floor(v.Z/size+0.5)*size
    )
end

function module.toCell(v, size)
    size = size or 1
    return Vector3.new(
        math.floor(v.X/size),
        math.floor(v.Y/size),
        math.floor(v.Z/size)
    )
end

return module
