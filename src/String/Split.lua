local module = {}

function module.split(str, sep)
    sep = sep or " "
    local out = {}
    for s in string.gmatch(str, "([^"..sep.."]+)") do
        out[#out+1] = s
    end
    return out
end

return module
