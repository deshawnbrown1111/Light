local module = {}

function module.normalize(str)
    return string.lower(string.gsub(str, "%s+", ""))
end

return module
