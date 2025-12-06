local module = {}

function module.new()
    return {
        walk_when_air = false,
        max_fall_distance = 10,
        exploration_paths = 5,
        exploration_visualize_time = 2,
        cell_size = 3,
        jump_penalty = 1.5,
        fall_penalty = 0.8,
        prefer_ground = true
    }
end

function module.set(config, key, value)
    if config[key] ~= nil then
        config[key] = value
        return true
    end
    return false
end

function module.get(config, key)
    return config[key]
end

return module
