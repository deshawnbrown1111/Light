local module = {}

function module.heuristic(a, b)
    return (a - b).Magnitude
end

function module.weight(dist, penalty)
    return dist + penalty
end

return module
