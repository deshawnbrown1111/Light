local module = {}

function module.distance(a, b)
    return (a - b).Magnitude
end

function module.direction(a, b)
    return (b - a).Unit
end

function module.angle(v1, v2)
    return math.deg(math.acos(math.clamp(v1:Dot(v2) / (v1.Magnitude * v2.Magnitude), -1, 1)))
end

return module
