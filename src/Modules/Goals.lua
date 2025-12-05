local Vector = import("Math/Vector")
local Pathfinder = import("Modules/Pathfinder")
local Controller = import("Modules/Controller")

local module = {}

function module.new(type, data)
    return {
        type = type,
        data = data,
        active = false,
        completed = false,
        failed = false
    }
end

function module.createGoto(position)
    return module.new("goto", {
        target = position
    })
end

function module.createFollow(player, distance)
    return module.new("follow", {
        target = player,
        distance = distance or 5
    })
end

function module.createMine(blockType)
    return module.new("mine", {
        blockType = blockType
    })
end

function module.createIdle()
    return module.new("idle", {})
end

function module.execute(goal, pathfinder, controller)
    if goal.active then return end
    
    goal.active = true
    
    if goal.type == "goto" then
        module.executeGoto(goal, pathfinder, controller)
    elseif goal.type == "follow" then
        module.executeFollow(goal, pathfinder, controller)
    elseif goal.type == "mine" then
        module.executeMine(goal, pathfinder, controller)
    elseif goal.type == "idle" then
        module.executeIdle(goal, controller)
    end
end

function module.executeGoto(goal, pathfinder, controller)
    local Players = game:GetService("Players")
    local plr = Players.LocalPlayer
    local char = plr.Character
    if not char then
        goal.failed = true
        return
    end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        goal.failed = true
        return
    end
    
    local startPos = hrp.Position
    local targetPos = goal.data.target
    
    local path = Pathfinder.findAndSmooth(pathfinder, startPos, targetPos)
    
    if not path then
        goal.failed = true
        return
    end
    
    controller.onComplete = function()
        goal.completed = true
        goal.active = false
    end
    
    controller.onStuck = function()
        goal.failed = true
        goal.active = false
    end
    
    Controller.setPath(controller, path)
    Controller.start(controller)
end

function module.executeFollow(goal, pathfinder, controller)
    local Players = game:GetService("Players")
    local plr = Players.LocalPlayer
    local RunService = game:GetService("RunService")
    
    local targetPlayer = goal.data.target
    local followDist = goal.data.distance
    
    local updateConn
    updateConn = RunService.Heartbeat:Connect(function()
        if goal.completed or goal.failed then
            updateConn:Disconnect()
            return
        end
        
        local char = plr.Character
        local targetChar = targetPlayer.Character
        
        if not char or not targetChar then
            goal.failed = true
            updateConn:Disconnect()
            return
        end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local targetHrp = targetChar:FindFirstChild("HumanoidRootPart")
        
        if not hrp or not targetHrp then
            goal.failed = true
            updateConn:Disconnect()
            return
        end
        
        local dist = Vector.distance(hrp.Position, targetHrp.Position)
        
        if dist > followDist + 3 then
            local path = Pathfinder.findAndSmooth(pathfinder, hrp.Position, targetHrp.Position)
            
            if path then
                Controller.setPath(controller, path)
                if not Controller.isRunning(controller) then
                    Controller.start(controller)
                end
            end
        elseif dist <= followDist then
            Controller.stop(controller)
        end
    end)
end

function module.executeMine(goal, pathfinder, controller)
    goal.failed = true
end

function module.executeIdle(goal, controller)
    Controller.stop(controller)
    goal.completed = true
end

function module.cancel(goal, controller)
    goal.active = false
    goal.failed = true
    Controller.stop(controller)
end

function module.isActive(goal)
    return goal.active
end

function module.isCompleted(goal)
    return goal.completed
end

function module.isFailed(goal)
    return goal.failed
end

return module
