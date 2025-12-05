local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Signal = {}
Signal.__index = Signal
function Signal.new()
	local self = setmetatable({_cbs = {}}, Signal)
	return self
end
function Signal:Connect(fn)
	local id = {}
	self._cbs[id] = fn
	return {
		Disconnect = function()
			self._cbs[id] = nil
		end
	}
end
function Signal:Fire(...)
	for _,cb in pairs(self._cbs) do
		task.spawn(cb, ...)
	end
end

local Eyes = {}
Eyes.__index = Eyes

function Eyes.new(opts)
	local o = opts or {}
	local self = setmetatable({}, Eyes)
	self.predictionTime = o.predictionTime or 0.18
	self.maxPredictionTime = o.maxPredictionTime or 1
	self.velSmooth = o.velSmooth or 0.3
	self.accelSmooth = o.accelSmooth or 0.25
	self.updateRate = o.updateRate or 1/60
	self.historyPeriod = o.historyPeriod or 0.25
	self.snapToGround = (o.snapToGround ~= false)
	self.groundRayDistance = o.groundRayDistance or 6
	self._players = {}
	self._running = false
	self._lastHeartbeat = 0
	self._nearest = nil
	self._farthest = nil
	self.Changed = Signal.new()
	self._conns = {}
	self._rayParams = RaycastParams.new()
	self._rayParams.FilterDescendantsInstances = {}
	self._rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	self._rayParams.IgnoreWater = true
	return self
end

function Eyes:_getRoot(plr)
	local ch = plr.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart")
end

function Eyes:_ensurePlayer(plr)
	local id = plr.UserId
	local now = tick()
	if self._players[id] then return end
	local root = self:_getRoot(plr)
	local humanoid = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	local p = {
		player = plr,
		root = root,
		humanoid = humanoid,
		lastPos = root and root.Position or nil,
		lastTime = root and now or nil,
		vel = Vector3.new(),
		accel = Vector3.new(),
		air = false,
		predicted = nil,
		distance = math.huge
	}
	self._players[id] = p
	if plr.CharacterAdded then
		self._conns["charAdded"..id] = plr.CharacterAdded:Connect(function(ch)
			p.root = ch:WaitForChild("HumanoidRootPart", 5)
			p.humanoid = ch:FindFirstChildOfClass("Humanoid")
			p.lastPos = p.root and p.root.Position or nil
			p.lastTime = tick()
		end)
	end
	if plr.CharacterRemoving then
		self._conns["charRemoving"..id] = plr.CharacterRemoving:Connect(function()
			p.root = nil
			p.humanoid = nil
			p.lastPos = nil
			p.lastTime = nil
			p.vel = Vector3.new()
			p.accel = Vector3.new()
		end)
	end
end

function Eyes:_cleanupPlayer(plr)
	local id = plr.UserId
	local p = self._players[id]
	if not p then return end
	self._players[id] = nil
	local ca = self._conns["charAdded"..id]
	if ca then ca:Disconnect(); self._conns["charAdded"..id] = nil end
	local cr = self._conns["charRemoving"..id]
	if cr then cr:Disconnect(); self._conns["charRemoving"..id] = nil end
end

function Eyes:_updatePlayerState(p, now)
	local root = p.root
	if not root then
		local r = self:_getRoot(p.player)
		if r then
			p.root = r
			p.lastPos = r.Position
			p.lastTime = now
		else
			return
		end
	end
	local pos = root.Position
	local dt = math.max(1e-6, now - (p.lastTime or now))
	local rawVel = (pos - (p.lastPos or pos)) / dt
	p.vel = p.vel:Lerp(rawVel, math.clamp(self.velSmooth, 0, 1))
	local rawAccel = (p.vel - (p.prevVel or p.vel)) / dt
	p.accel = p.accel:Lerp(rawAccel, math.clamp(self.accelSmooth, 0, 1))
	p.prevVel = p.vel
	p.lastPos = pos
	p.lastTime = now
	local hum = p.humanoid or (p.player.Character and p.player.Character:FindFirstChildOfClass("Humanoid"))
	p.humanoid = hum
	local stateAir = false
	if hum then
		local st = hum:GetState()
		if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then
			stateAir = true
		end
	end
	if root.Velocity and math.abs(root.Velocity.Y) > 3 then stateAir = true end
	p.air = stateAir
end

function Eyes:_predictFor(p, t)
	t = math.clamp(t, 0, self.maxPredictionTime)
	local pos = p.lastPos or (p.root and p.root.Position) or Vector3.new()
	local v = p.vel or Vector3.new()
	local a = p.accel or Vector3.new()
	local g = Workspace.Gravity or 196.2
	local predicted = pos + v * t + 0.5 * a * (t * t)
	if p.air then
		predicted = predicted + Vector3.new(0, -0.5 * g * (t * t), 0)
	end
	if self.snapToGround then
		local rayOrigin = predicted + Vector3.new(0, self.groundRayDistance * 0.5, 0)
		local rayDir = Vector3.new(0, -self.groundRayDistance, 0)
		local rp = self._rayParams
		local ignoreList = rp.FilterDescendantsInstances
		table.clear(ignoreList)
		local ch = p.player.Character
		if ch then
			table.insert(ignoreList, ch)
		end
		table.insert(ignoreList, LocalPlayer.Character or LocalPlayer.Character)
		local r = Workspace:Raycast(rayOrigin, rayDir, rp)
		if r then
			local hitY = r.Position.Y
			if predicted.Y < hitY + 0.5 then
				predicted = Vector3.new(predicted.X, hitY, predicted.Z)
			end
		end
	end
	return predicted
end

function Eyes:updateOnce()
	local now = tick()
	local lpRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not lpRoot then return end
	local lpPos = lpRoot.Position
	for _,plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			self:_ensurePlayer(plr)
		end
	end
	for id,p in pairs(self._players) do
		if not p.player or not p.player.Parent then
			self._players[id] = nil
		else
			if not p.root then
				p.root = self:_getRoot(p.player)
				if p.root then
					p.lastPos = p.root.Position
					p.lastTime = now
				end
			end
			if p.root then
				self:_updatePlayerState(p, now)
				local predicted = self:_predictFor(p, self.predictionTime)
				p.predicted = predicted
				local dist = (p.lastPos - lpPos).Magnitude
				p.distance = dist
			end
		end
	end
	local nearest, farthest = nil, nil
	local nDist, fDist = math.huge, -math.huge
	for _,p in pairs(self._players) do
		if p.lastPos then
			if p.distance < nDist then
				nDist = p.distance
				nearest = p
			end
			if p.distance > fDist then
				fDist = p.distance
				farthest = p
			end
		end
	end
	local changed = false
	if (nearest and (not self._nearest or self._nearest.player ~= nearest.player)) or (not nearest and self._nearest) then
		self._nearest = nearest
		changed = true
	end
	if (farthest and (not self._farthest or self._farthest.player ~= farthest.player)) or (not farthest and self._farthest) then
		self._farthest = farthest
		changed = true
	end
	if changed then
		self.Changed:Fire(self._nearest, self._farthest)
	end
end

function Eyes:start()
	if self._running then return end
	self._running = true
	self._lastHeartbeat = 0
	self._conns["heartbeat"] = RunService.Heartbeat:Connect(function(dt)
		self._lastHeartbeat = self._lastHeartbeat + dt
		if self._lastHeartbeat >= self.updateRate then
			self._lastHeartbeat = 0
			self:updateOnce()
		end
	end)
	self._conns["playerAdded"] = Players.PlayerAdded:Connect(function(plr) end)
	self._conns["playerRemoving"] = Players.PlayerRemoving:Connect(function(plr)
		self:_cleanupPlayer(plr)
	end)
end

function Eyes:stop()
	if not self._running then return end
	self._running = false
	for k,v in pairs(self._conns) do
		if v and v.Disconnect then
			pcall(function() v:Disconnect() end)
		end
		self._conns[k] = nil
	end
	self._players = {}
	self._nearest = nil
	self._farthest = nil
end

function Eyes:setPredictionTime(t)
	self.predictionTime = math.clamp(t or self.predictionTime, 0, self.maxPredictionTime)
end

function Eyes:setUpdateRate(r)
	self.updateRate = math.max(1/240, r or self.updateRate)
end

function Eyes:getNearest()
	return self._nearest
end

function Eyes:getFarthest()
	return self._farthest
end

function Eyes:getSortedByDistance(n)
	local arr = {}
	for _,p in pairs(self._players) do
		if p.lastPos then table.insert(arr, p) end
	end
	table.sort(arr, function(a,b) return a.distance < b.distance end)
	if n and #arr > n then
		local out = {}
		for i=1,n do out[i]=arr[i] end
		return out
	end
	return arr
end

return Eyes
