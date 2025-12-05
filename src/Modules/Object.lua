local Players = game:GetService("Players")
local plr = Players.LocalPlayer

local module = {}

local dirs = {
    front = Vector3.new(0,0,-1),
    back = Vector3.new(0,0,1),
    left = Vector3.new(-1,0,0),
    right = Vector3.new(1,0,0),
    up = Vector3.new(0,1,0),
    down = Vector3.new(0,-1,0)
}

function module.Check(dir, dist)
    dir = string.lower(dir)
    dist = dist or 5

    local char = plr.Character or plr.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart")

    local lookCF = hrp.CFrame
    local baseDir = dirs[dir]
    if not baseDir then return false end

    local worldDir = (lookCF:VectorToWorldSpace(baseDir)) * dist

    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {char}
    params.FilterType = Enum.RaycastFilterType.Blacklist

    local result = workspace:Raycast(hrp.Position, worldDir, params)

    if result and result.Instance then
        return true, result.Instance
    end

    return false, nil
end

return module
