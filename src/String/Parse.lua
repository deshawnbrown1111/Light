local module = {}

function module.toNumberList(str)
    local out = {}
    for n in string.gmatch(str, "%-?%d+%.?%d*") do
        out[#out+1] = tonumber(n)
    end
    return out
end

function module.toVector3(str)
    local nums = module.toNumberList(str)
    return Vector3.new(nums[1], nums[2], nums[3])
end

return module
