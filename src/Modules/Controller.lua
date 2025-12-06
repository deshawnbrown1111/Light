local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Movement = import("Math/Movement")
local Vector = import("Math/Vector")
local Grid = import("Math/Grid")
local Object = import("Modules/Object")
local Visualizer = import("Modules/Visualizer")

local module = {}

function module.new(opts)
    opts = opts or {}
    return {
        player = Players.LocalPlayer,
        path = {},
        currentIndex = 1,
        running = false,
        waypointReachedDist = opts.waypointReachedDist or 2,
        moveSpeed = opts.moveSpeed or 16,
        stuckThreshold = opts.stuckThreshold or 3,
        stuckTime = 0,
        lastPos = nil,
        onComplete = nil,
        onStuck = nil,
        conn = nil,
        visualizer = opts.visualizer or nil
    }
end

function module.setPath(controller, path)
    controller.path = path
    controller.currentIndex = 1
    controller.stuckTime = 0
    
    if controller.visualizer then
        Visualizer.drawPath(controller.visualizer, path, 1)
    end
end

function module.getNextWaypoint(controller)
    if controller.currentIndex > #controller.path then
        return nil
    end
    return controller.path[controller.currentIndex]
end

function module.isStuck(controller, currentPos, dt)
    if not controller.lastPos then
        controller.lastPos = currentPos
        return false
    end
    
    local moved = Vector.distance(currentPos, controller.lastPos)
    
    if moved < 0.1 then
        controller.stuckTime = controller.stuckTime + dt
    else
        controller.stuckTime = 0
    end
    
    controller.lastPos = currentPos
    
    return controller.stuckTime > controller.stuckThreshold
end

function module.moveTowards(controller, target)
    local char = controller.player.Character
    if not char then return false end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChild("Humanoid")
    
    if not hrp or not humanoid then return false end
    
    local currentPos = hrp.Position
    local direction = Vector.direction(currentPos, target)
    local horizontalDir = Movement.toHorizontal(direction)
    
    if horizontalDir.Magnitude > 0.1 then
        humanoid:MoveTo(currentPos + horizontalDir * 100)
    end
    
    local dist = Vector.distance(Movement.toHorizontal(currentPos), Movement.toHorizontal(target))
    
    if target.Y > currentPos.Y + 2 then
        humanoid.Jump = true
    end
    
    return dist < controller.waypointReachedDist
end

function module.update(controller, dt)
    if not controller.running then return end
    
    local char = controller.player.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local waypoint = module.getNextWaypoint(controller)
    
    if not waypoint then
        module.stop(controller)
        if controller.onComplete then
            controller.onComplete()
        end
        return
    end
    
    if module.isStuck(controller, hrp.Position, dt) then
        module.stop(controller)
        if controller.onStuck then
            controller.onStuck()
        end
        return
    end
    
    local reached = module.moveTowards(controller, waypoint)
    
    if reached then
        controller.currentIndex = controller.currentIndex + 1
        
        if controller.visualizer then
            Visualizer.updateCurrentIndex(controller.visualizer, controller.path, controller.currentIndex)
        end
    end
end

function module.start(controller)
    if controller.running then return end
    
    controller.running = true
    controller.currentIndex = 1
    controller.stuckTime = 0
    controller.lastPos = nil
    
    controller.conn = RunService.Heartbeat:Connect(function(dt)
        module.update(controller, dt)
    end)
end

function module.stop(controller)
    if not controller.running then return end
    
    controller.running = false
    
    if controller.conn then
        controller.conn:Disconnect()
        controller.conn = nil
    end
    
    if controller.visualizer then
        Visualizer.clear(controller.visualizer)
    end
    
    local char = controller.player.Character
    if char then
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:MoveTo(char:FindFirstChild("HumanoidRootPart").Position)
        end
    end
end

function module.isRunning(controller)
    return controller.running
end

return module
