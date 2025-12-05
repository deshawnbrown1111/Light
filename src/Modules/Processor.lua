local Eyes = loadstring(game:HttpGet("https://raw.githubusercontent.com/deshawnbrown1111/Light/refs/heads/main/src/Modules/Prediction.lua"))()

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Processor = {}
Processor.__index = Processor

local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function now() return tick() end
local function copyVec(v) return Vector3.new(v.X,v.Y,v.Z) end
local function vecMag(v) return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end

local function linearRegressionVelocity(samples)
	if #samples < 2 then return Vector3.new() end
	local n = #samples
	local mean_t = 0
	for i=1,n do mean_t = mean_t + samples[i].t end
	mean_t = mean_t / n
	local mean_x, mean_y, mean_z = 0,0,0
	for i=1,n do
		local p = samples[i].pos
		mean_x = mean_x + p.X
		mean_y = mean_y + p.Y
		mean_z = mean_z + p.Z
	end
	mean_x = mean_x / n
	mean_y = mean_y / n
	mean_z = mean_z / n
	local denom, covx, covy, covz = 0,0,0,0
	for i=1,n do
		local dt = samples[i].t - mean_t
		denom = denom + dt * dt
		local px = samples[i].pos.X - mean_x
		local py = samples[i].pos.Y - mean_y
		local pz = samples[i].pos.Z - mean_z
		covx = covx + dt * px
		covy = covy + dt * py
		covz = covz + dt * pz
	end
	if denom == 0 then return Vector3.new() end
	return Vector3.new(covx/denom, covy/denom, covz/denom)
end

local DEFAULTS = {
	historyPeriod = 0.30,
	minSamples = 3,
	maxSamples = 30,
	updateRate = 1/120,
	maxSpeed = 80,
	teleportFactor = 2.5,
	basePrediction = 0.12,
	predictionScale = 0.10,
	maxPrediction = 0.6,
	rmseWindow = 90,
	idleSpeed = 0.7,
	walkSpeed = 6,
	runSpeed = 14,
	turnRateThreshold = 1.2,
	arcPredictScale = 0.5,
	alphaBetaEnableRMSE = 6.0,
	alphaBetaAlpha = 0.6,
	alphaBetaBeta = 0.4,
	autoTune = true,
	autoTuneLR = 0.01
}

local function computeTurnRate(samples)
	if #samples < 3 then return 0 end
	local total = 0
	local count = 0
	for i=2,#samples-1 do
		local a = samples[i-1].pos
		local b = samples[i].pos
		local c = samples[i+1].pos
		local v1 = (b - a)
		local v2 = (c - b)
		if v1.Magnitude > 1e-4 and v2.Magnitude > 1e-4 then
			local n1 = v1.Unit
			local n2 = v2.Unit
			local dot = clamp(n1:Dot(n2), -1, 1)
			local ang = math.acos(dot)
			local dt = (samples[i+1].t - samples[i-1].t)
			if dt > 1e-6 then
				total = total + (ang / dt)
				count = count + 1
			end
		end
	end
	return (count > 0) and (total / count) or 0
end

local function arcPredict(pos, vel, turnRate, t)
	if math.abs(turnRate) < 1e-6 then
		return pos + vel * t
	end
	local speed = vecMag(vel)
	if speed < 1e-4 then return pos end
	local radius = speed / turnRate
	local forward = Vector3.new(vel.X, 0, vel.Z).Unit
	local right = Vector3.new(forward.Z, 0, -forward.X)
	local dir = (turnRate > 0) and right or -right
	local center = pos + dir * radius
	local theta = turnRate * t
	local offset = pos - center
	local cosT = math.cos(theta)
	local sinT = math.sin(theta)
	local x = offset.X * cosT - offset.Z * sinT
	local z = offset.X * sinT + offset.Z * cosT
	local newOffset = Vector3.new(x, offset.Y, z)
	return center + newOffset + vel.Y * Vector3.new(0,1,0) * t
end

function Processor.new(eyes, opts)
	assert(eyes, "Processor requires Eyes instance")
	local self = setmetatable({}, Processor)
	self.eyes = eyes
	self.opts = {}
	for k,v in pairs(DEFAULTS) do self.opts[k] = (opts and opts[k] ~= nil) and opts[k] or v end
	self._running = false
	self._conns = {}
	self._buffers = {}
	self._lastTick = 0
	self._stats = {totalSamples = 0, processed = 0}
	return self
end

function Processor:_ensureBuffer(id)
	local b = self._buffers[id]
	if b then return b end
	b = {
		samples = {},
		speedEWMA = 0,
		rmseBuf = {},
		lastPred = nil,
		lastPredT = nil,
		state = "unknown",
		lastVel = Vector3.new(),
		lastDt = 0,
		predScale = self.opts.predictionScale,
		alphaBeta = {x = nil, v = nil},
		failCount = 0
	}
	self._buffers[id] = b
	return b
end

function Processor:_isTeleport(prevPos, curPos, dt, maxSpeed)
	if not prevPos or not curPos then return false end
	local disp = (curPos - prevPos).Magnitude
	local maxDisp = (maxSpeed or self.opts.maxSpeed) * (dt + 0.05) * self.opts.teleportFactor
	return disp > maxDisp
end

function Processor:_adaptivePredictionTime(speed, predScale)
	local base = self.opts.basePrediction
	local scale = predScale or self.opts.predictionScale
	local maxT = self.opts.maxPrediction
	local maxSpeed = self.opts.maxSpeed
	local t = base + scale * clamp(speed / maxSpeed, 0, 1)
	if t > maxT then t = maxT end
	return t
end

function Processor:_classify(speed, p)
	if p.air then return "air" end
	if speed < self.opts.idleSpeed then return "idle" end
	if speed < self.opts.walkSpeed then return "walk" end
	if speed < self.opts.runSpeed then return "run" end
	return "sprint"
end

function Processor:_alphaBetaPredict(b, t_pred)
	local st = b.alphaBeta
	if not st.x then
		if #b.samples == 0 then return nil end
		st.x = b.samples[#b.samples].pos
		st.v = b.lastVel or Vector3.new()
	end
	local x = st.x
	local v = st.v
	local pred = x + v * t_pred
	return pred
end

function Processor:_processEntry(id, pdata)
	local p = pdata
	if not p or not p.player then return end
	local root = p.root
	if not root then return end
	local b = self:_ensureBuffer(id)
	local t = now()
	local pos = root.Position
	table.insert(b.samples, {t = t, pos = copyVec(pos)})
	local cutoff = t - (self.opts.historyPeriod or 0.25)
	while #b.samples > 0 and b.samples[1].t < cutoff do table.remove(b.samples,1) end
	if #b.samples > self.opts.maxSamples then
		local removeCount = #b.samples - self.opts.maxSamples
		for i=1,removeCount do table.remove(b.samples,1) end
	end
	if #b.samples < self.opts.minSamples then return end
	local oldest = b.samples[1]
	local newest = b.samples[#b.samples]
	local dt = math.max(1e-6, newest.t - oldest.t)
	if self:_isTeleport(oldest.pos, newest.pos, dt, self.opts.maxSpeed) then
		b.samples = { newest }
		b.lastPred = nil
		b.lastPredT = nil
		b.speedEWMA = 0
		b.state = "teleport"
		b.failCount = b.failCount + 1
		return
	end
	local v = linearRegressionVelocity(b.samples)
	local speed = vecMag(v)
	local alpha = 0.25
	b.speedEWMA = b.speedEWMA * (1 - alpha) + speed * alpha
	local state = self:_classify(b.speedEWMA, p)
	b.state = state
	local turnRate = computeTurnRate(b.samples)
	b.turnRate = turnRate
	local predScale = b.predScale or self.opts.predictionScale
	local t_pred = self:_adaptivePredictionTime(b.speedEWMA, predScale)
	local a = p.accel or Vector3.new()
	local predicted
	if math.abs(turnRate) > self.opts.turnRateThreshold and b.speedEWMA > 1 then
		local arc = arcPredict(newest.pos, v, turnRate, t_pred)
		local straight = newest.pos + v * t_pred + 0.5 * a * (t_pred * t_pred)
		local blend = clamp((math.abs(turnRate) - self.opts.turnRateThreshold) / (self.opts.turnRateThreshold*2), 0, 1)
		predicted = straight:Lerp(arc, blend * self.opts.arcPredictScale)
	else
		predicted = newest.pos + v * t_pred + 0.5 * a * (t_pred * t_pred)
	end
	if p.air then
		local g = workspace.Gravity or 196.2
		predicted = predicted + Vector3.new(0, -0.5 * g * (t_pred * t_pred), 0)
	end
	local rmseNow = 0
	table.insert(b.rmseBuf, (predicted - newest.pos).Magnitude)
	if #b.rmseBuf > self.opts.rmseWindow then table.remove(b.rmseBuf, 1) end
	local sumsq = 0
	for i=1,#b.rmseBuf do sumsq = sumsq + (b.rmseBuf[i]^2) end
	if #b.rmseBuf > 0 then rmseNow = math.sqrt(sumsq / #b.rmseBuf) end
	b.rmse = rmseNow
	if rmseNow > self.opts.alphaBetaEnableRMSE then
		local ab = self:_alphaBetaPredict(b, t_pred)
		if ab then
			local factor = clamp((rmseNow - self.opts.alphaBetaEnableRMSE)/ (self.opts.alphaBetaEnableRMSE*2), 0, 1)
			predicted = predicted:Lerp(ab, factor)
		end
	end
	if self.opts.autoTune then
		local target = clamp(1 / (1 + rmseNow), 0.02, 0.5)
		local lr = self.opts.autoTuneLR
		local adjustment = lr * (target - predScale)
		predScale = clamp(predScale + adjustment, 0.02, 0.5)
		b.predScale = predScale
	end
	local eyesPlayers = self.eyes._players
	if eyesPlayers and eyesPlayers[id] then
		eyesPlayers[id].predicted = predicted
	end
	b.lastPred = predicted
	b.lastPredT = t
	b.lastVel = v
	b.lastDt = dt
	if rmseNow > 3 then
		b.failCount = b.failCount + 1
	else
		b.failCount = math.max(0, b.failCount - 1)
	end
	self._stats.totalSamples = self._stats.totalSamples + 1
end

function Processor:_processAll()
	local eyesPlayers = self.eyes._players
	for id, pdata in pairs(eyesPlayers) do
		pcall(function() self:_processEntry(id, pdata) end)
	end
end

function Processor:start()
	if self._running then return end
	self._running = true
	self._lastTick = 0
	self._conns.heartbeat = RunService.Heartbeat:Connect(function(dt)
		self._lastTick = self._lastTick + dt
		if self._lastTick >= (self.opts.updateRate or 1/120) then
			self._lastTick = 0
			self:_processAll()
		end
	end)
	self._conns.playerRemoving = Players.PlayerRemoving:Connect(function(plr)
		self._buffers[plr.UserId] = nil
	end)
end

function Processor:stop()
	if not self._running then return end
	self._running = false
	for k,v in pairs(self._conns) do
		if v and v.Disconnect then
			pcall(function() v:Disconnect() end)
		end
		self._conns[k] = nil
	end
	self._buffers = {}
end

function Processor:GetPlayerStats(playerOrId)
	local id = (typeof(playerOrId) == "Instance" and playerOrId.UserId) or playerOrId
	local b = self._buffers[id]
	if not b then
		local p = self.eyes._players[id]
		if p then b = self:_ensureBuffer(id) end
	end
	if not b then return nil end
	return {
		rmse = b.rmse or 0,
		speedEWMA = b.speedEWMA or 0,
		lastVel = b.lastVel or Vector3.new(),
		lastDt = b.lastDt or 0,
		state = b.state or "unknown",
		samples = #b.samples,
		lastPred = b.lastPred,
		predScale = b.predScale
	}
end

function Processor:GetOverallStats()
	return {
		totalSamples = self._stats.totalSamples or 0
	}
end

function Processor:SetOptions(opts)
	for k,v in pairs(opts or {}) do
		self.opts[k] = v
	end
end

function Processor:ForceRecompute()
	self:_processAll()
end

return {Eyes = Eyes, Processor = Processor}
