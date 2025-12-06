return function(path)
    path = path:gsub("%.lua$", "")
    local BASE = "https://raw.githubusercontent.com/deshawnbrown1111/Light/refs/heads/main/src/"
    local cache = getgenv().__import_cache or {}
    getgenv().__import_cache = cache

    getgenv().import = getgenv().import or function(p)
        p = p:gsub("%.lua$", "")
        if cache[p] then
            return cache[p]
        end
        local url = BASE .. p .. ".lua"
        local source = game:HttpGet(url)
        local module = loadstring(source, p)()
        cache[p] = module
        return module
    end

    return getgenv().import(path)
end
