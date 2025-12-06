local module = {}

function module.new(opts)
    opts = opts or {}
    return {
        enabled = opts.enabled ~= false,
        lineThickness = opts.lineThickness or 0.1,
        pathColor = opts.pathColor or Color3.fromRGB(0, 255, 255),
        nextColor = opts.nextColor or Color3.fromRGB(0, 255, 0),
        goalColor = opts.goalColor or Color3.fromRGB(255, 0, 0),
        parts = {},
        folder = nil
    }
end

function module.createLine(viz, startPos, endPos, color)
    local distance = (endPos - startPos).Magnitude
    local midpoint = (startPos + endPos) / 2
    
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(viz.lineThickness, viz.lineThickness, distance)
    part.CFrame = CFrame.new(midpoint, endPos)
    part.Color = color
    part.Material = Enum.Material.Neon
    part.Transparency = 0.3
    
    if not viz.folder then
        viz.folder = Instance.new("Folder")
        viz.folder.Name = "PathVisualizer"
        viz.folder.Parent = workspace
    end
    
    part.Parent = viz.folder
    table.insert(viz.parts, part)
    
    return part
end

function module.clear(viz)
    for i = 1, #viz.parts do
        if viz.parts[i] then
            viz.parts[i]:Destroy()
        end
    end
    viz.parts = {}
end

function module.drawPath(viz, path, currentIndex)
    if not viz.enabled then return end
    if not path or #path == 0 then return end
    
    module.clear(viz)
    
    currentIndex = currentIndex or 1
    
    for i = 1, #path - 1 do
        local startPos = path[i]
        local endPos = path[i + 1]
        
        local color = viz.pathColor
        
        if i == currentIndex then
            color = viz.nextColor
        elseif i == #path - 1 then
            color = viz.goalColor
        end
        
        module.createLine(viz, startPos, endPos, color)
    end
    
    if #path > 0 then
        local goalMarker = Instance.new("Part")
        goalMarker.Anchored = true
        goalMarker.CanCollide = false
        goalMarker.Size = Vector3.new(1, 3, 1)
        goalMarker.Position = path[#path]
        goalMarker.Color = viz.goalColor
        goalMarker.Material = Enum.Material.Neon
        goalMarker.Transparency = 0.5
        goalMarker.Shape = Enum.PartType.Cylinder
        goalMarker.Parent = viz.folder
        table.insert(viz.parts, goalMarker)
    end
end

function module.updateCurrentIndex(viz, path, currentIndex)
    if not viz.enabled then return end
    module.drawPath(viz, path, currentIndex)
end

function module.enable(viz)
    viz.enabled = true
end

function module.disable(viz)
    viz.enabled = false
    module.clear(viz)
end

function module.toggle(viz)
    if viz.enabled then
        module.disable(viz)
    else
        module.enable(viz)
    end
end

return module
