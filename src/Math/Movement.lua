local module = {}

function module.toHorizontal(v)
    return Vector3.new(v.X, 0, v.Z)
end

function module.rotateTowards(current, target, step)
    local diff = target - current
    if diff.Magnitude <= step then return target end
    return current + diff.Unit * step
end

function module.lerp(a, b, t)
    return a + (b - a) * t
end

return module
