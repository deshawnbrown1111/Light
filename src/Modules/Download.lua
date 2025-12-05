assert(getcustomasset, "[!] Dumbass")

local HttpService = game:GetService("HttpService")
local function try_request(url)
    local ok, res = pcall(function()
        if syn and syn.request then return syn.request({Url = url, Method = "GET"}) end
        if request then return request({Url = url, Method = "GET"}) end
        if http_request then return http_request({Url = url, Method = "GET"}) end
        if http and http.request then return http.request({Url = url, Method = "GET"}) end
        return {Body = HttpService:GetAsync(url)}
    end)
    if not ok then return nil, res end
    return res, nil
end

local function Download(url)
    if not url then return nil end
    local filename = url:match("([^/]+)$") or "texture_asset"
    local localname = "asset_downloaded_" .. filename
    local response, err = try_request(url)
    if not response then
        return url
    end
    local body = response.Body or response
    local ok, werr = pcall(function()
        if writefile then
            writefile(localname, body)
        else
            local f = assert(io.open(localname, "wb"))
            f:write(body)
            f:close()
        end
    end)
    if not ok then
        local ok2, asset = pcall(function()
            return getcustomasset(localname)
        end)
        if ok2 then return asset end
        return url
    end
    local ok3, asset = pcall(function()
        return getcustomasset(localname)
    end)
    if ok3 then return asset end
    return url
end

return Download
