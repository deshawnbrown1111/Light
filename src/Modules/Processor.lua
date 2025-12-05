local Eyes = loadstring(game:HttpGet("https://raw.githubusercontent.com/deshawnbrown1111/Light/refs/heads/main/src/Modules/Prediction.lua"))()

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Processor = {}
Processor.__index = Processor

local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function now() return tick() end
local function copyVec(v) return Vector3.new(v.X,v.Y,v.Z) end
local function vecMag(v) return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end

local function weightedLinearVelocity(samples)
	if #samples < 2 then return Vector3.new() end
	local n = #samples
	local tmax = samples[n].t
	local tau = math.max(0.06, (tmax - samples[1].t) * 0.5)
	local sw, st, sx, sy, sz, stt, stx, sty, stz = 0,0,0,0,0,0,0,0,0
	for i=1,n do
		local s = samples[i]
		local dt = tmax - s.t
		local w = math.exp(-dt / math.max(tau,1e-6))
		local t = s.t
		local p = s.pos
		sw = sw + w
		st = st + w * t
		sx = sx + w * p.X
		sy = sy + w * p.Y
		sz = sz + w * p.Z
	end
	local mean_t = st / sw
	local mean_x, mean_y, mean_z = sx/sw, sy/sw, sz/sw
	local denom = 0
	local covx, covy, covz = 0,0,0
	for i=1,n do
		local s = samples[i]
		local w = math.exp(-(tmax - s.t) / math.max(tau,1e-6))
		local dt = s.t - mean_t
		denom = denom + w * dt * dt
		covx = covx + w * dt * (s.pos.X - mean_x)
		covy = covy + w * dt * (s.pos.Y - mean_y)
		covz = covz + w * dt * (s.pos.Z - mean_z)
	end
	if denom == 0 then return Vector3.new() end
	return Vector3.new(covx/denom, covy/denom, covz/denom)
end

local function sampleResidualStd(samples, v)
	if #samples < 2 then return 0 end
	local t0 = samples[1].t
	local sumsq = 0
	local n = 0
	for i=1,#samples do
		local expected = samples[1].pos + v * (samples[i].t - t0)
		local r = (samples[i].pos - expected).Magnitude
		sumsq = sumsq + r*r
		n = n + 1
	end
	if n == 0 then return 0 end
	return math.sqrt(sumsq / n)
end

local DEFAULTS = {
	historyPeriod = 0.30,
	minSamples = 3,
	maxSamples = 32,
	updateRate = 1/120,
	maxSpeed = 40,
	teleportFactor = 1.6,
	basePrediction = 0.12,
	predictionScale = 0.10,
	maxPrediction = 0.6,
	rmseWindow = 40,
	idleSpeed = 1.2,
	walkSpeed = 6,
	runSpeed = 14,
	turnRateThreshold = 1.6,
	arcPredictScale = 0.7,
	alphaBetaEnableRMSE = 6.5,
	autoTune = true,
	autoTuneLR = 0.02,
	airGravityScale = 0.9,
	idleDamping = 0.9,
	groundSnapThreshold = 0.5,
	maxBiasBlend = 0.6,
	failResetThreshold = 5,
	inconsistentStdThreshold = 4.5,
	maxPredictionClamp = 1.4,
	distancePredictionFactor = 0.22
}

local function computeTurnRate(samples)
	if #samples < 4 then return 0 end
	local total = 0
	local count = 0
	for i=2,#samples-1 do
		local a = samples[i-1].pos
		local b = samples[i].pos
		local c = samples[i+1].pos
		local v1 = b - a
		local v2 = c - b
		if v1.Magnitude > 0.5 and v2.Magnitude > 0.5 then
			local n1 = Vector3.new(v1.X,0,v1.Z).Unit
			local n2 = Vector3.new(v2.X,0,v2.Z).Unit
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
	local radius = speed / math.max(math.abs(turnRate), 0.1)
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
	return center + newOffset + Vector3.new(0, vel.Y * t, 0)
end

function Processor.new(eyes, opts)
	assert(eyes, "eyes")
	local self = setmetatable({}, Processor)
	self.eyes = eyes
	self.opts = {}
	for k,v in pairs(DEFAULTS) do self.opts[k] = (opts and opts[k] ~= nil) and opts[k] or v end
	self._running = false
	self._conns = {}
	self._buffers = {}
	self._lastTick = 0
	self._stats = {totalSamples = 0}
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
		failCount = 0,
		consecutiveIdle = 0,
		inconsistent = false
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

function Processor:_pruneOutliers(samples, maxSpeed)
	if #samples < 3 then return samples end
	for i=2,#samples do
		local a = samples[i-1].pos
		local b = samples[i].pos
		local dt = math.max(1e-6, samples[i].t - samples[i-1].t)
		local disp = (b - a).Magnitude
		local maxDisp = maxSpeed * (dt + 0.05) * (self.opts.teleportFactor * 0.95)
		if disp > maxDisp * 1.15 then
			local new = {}
			for j=i,#samples do table.insert(new, samples[j]) end
			return new
		end
	end
	return samples
end

function Processor:_adaptivePredictionTime(speed, predScale, state)
	local base = self.opts.basePrediction
	local scale = predScale or self.opts.predictionScale
	local maxT = self.opts.maxPrediction
	local maxSpeed = self.opts.maxSpeed
	if state == "idle" then
		return base * 0.25
	elseif state == "walk" then
		return base * 0.55
	elseif state == "air" then
		return base * 1.25
	end
	local t = base + scale * clamp(speed / maxSpeed, 0, 1)
	if t > maxT then t = maxT end
	return t
end

function Processor:_classify(speed, p)
	if p and p.air then return "air" end
	if speed < self.opts.idleSpeed then return "idle" end
	if speed < self.opts.walkSpeed then return "walk" end
	if speed < self.opts.runSpeed then return "run" end
	return "sprint"
end

function Processor:_alphaBetaPredict(b, t_pred)
	local st = b.alphaBeta or {}
	if not st.x then
		if #b.samples == 0 then return nil end
		st.x = b.samples[#b.samples].pos
		st.v = b.lastVel or Vector3.new()
		b.alphaBeta = st
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
	local cutoff = t - (self.opts.historyPeriod or 0.30)
	while #b.samples > 0 and b.samples[1].t < cutoff do table.remove(b.samples,1) end
	if #b.samples > self.opts.maxSamples then
		local removeCount = #b.samples - self.opts.maxSamples
		for i=1,removeCount do table.remove(b.samples,1) end
	end
	if #b.samples < self.opts.minSamples then
		local fallbackPred = (p.lastPos or pos) + (p.vel or Vector3.new()) * (self.opts.basePrediction or 0.12)
		if p and p.air then
			local g = workspace.Gravity or 196.2
			local gravityFactor = self.opts.airGravityScale
			fallbackPred = fallbackPred + Vector3.new(0, -0.5 * g * gravityFactor * ((self.opts.basePrediction or 0.12) ^ 2), 0)
		end
		local eyesPlayers = self.eyes._players
		if eyesPlayers and eyesPlayers[id] then
			eyesPlayers[id].predicted = fallbackPred
			eyesPlayers[id].processorPredicted = fallbackPred
		end
		b.lastPred = fallbackPred
		b.lastPredT = t
		return
	end
	b.samples = self:_pruneOutliers(b.samples, self.opts.maxSpeed)
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
		b.consecutiveIdle = 0
		return
	end
	local v = weightedLinearVelocity(b.samples)
	v = v:Lerp(b.lastVel or v, 0.42)
	local speed = vecMag(v)
	local alpha = 0.28
	b.speedEWMA = b.speedEWMA * (1 - alpha) + speed * alpha
	local state = self:_classify(b.speedEWMA, p)
	b.state = state
	if state == "idle" then
		b.consecutiveIdle = b.consecutiveIdle + 1
		if b.consecutiveIdle > 8 then
			v = v * self.opts.idleDamping
			b.speedEWMA = b.speedEWMA * 0.5
		end
	else
		b.consecutiveIdle = 0
	end
	local turnRate = computeTurnRate(b.samples)
	b.turnRate = turnRate
	local predScale = b.predScale or self.opts.predictionScale
	if state == "sprint" then
		predScale = predScale * (1 + clamp(speed / 28, 0, 1.3))
	end
	local t_pred = self:_adaptivePredictionTime(b.speedEWMA, predScale, state)
	if p and p.distance then
		local distFactor = clamp(p.distance / 120, 0, 1)
		t_pred = t_pred * (1 + self.opts.distancePredictionFactor * distFactor)
	end
	local resStd = sampleResidualStd(b.samples, v)
	if resStd > self.opts.inconsistentStdThreshold then
		b.inconsistent = true
		if resStd > (self.opts.inconsistentStdThreshold * 1.8) then
			predScale = predScale * 0.55
			t_pred = t_pred * 0.55
		else
			predScale = predScale * 0.82
			t_pred = t_pred * 0.85
		end
	else
		b.inconsistent = false
	end
	local a = p and p.accel or Vector3.new()
	if state == "idle" or state == "walk" then
		a = a * 0.28
	end
	local predicted
	if math.abs(turnRate) > self.opts.turnRateThreshold and b.speedEWMA > 2 then
		local arc = arcPredict(newest.pos, v, turnRate, t_pred)
		local straight = newest.pos + v * t_pred + 0.5 * a * (t_pred * t_pred)
		local blend = clamp((math.abs(turnRate) - self.opts.turnRateThreshold) / (self.opts.turnRateThreshold), 0, 1)
		predicted = straight:Lerp(arc, blend * self.opts.arcPredictScale)
	else
		predicted = newest.pos + v * t_pred + 0.5 * a * (t_pred * t_pred)
	end
	if p and p.air then
		local g = workspace.Gravity or 196.2
		local gravityFactor = self.opts.airGravityScale
		predicted = predicted + Vector3.new(0, -0.5 * g * gravityFactor * (t_pred * t_pred), 0)
	end
	if state == "idle" and predicted.Y > newest.pos.Y + self.opts.groundSnapThreshold then
		predicted = Vector3.new(predicted.X, newest.pos.Y, predicted.Z)
	end
	local rmseNow = 0
	table.insert(b.rmseBuf, (predicted - newest.pos).Magnitude)
	if #b.rmseBuf > self.opts.rmseWindow then table.remove(b.rmseBuf, 1) end
	local sumsq = 0
	for i=1,#b.rmseBuf do sumsq = sumsq + (b.rmseBuf[i]^2) end
	if #b.rmseBuf > 0 then rmseNow = math.sqrt(sumsq / #b.rmseBuf) end
	b.rmse = rmseNow
	if rmseNow > self.opts.alphaBetaEnableRMSE and state ~= "idle" then
		local ab = self:_alphaBetaPredict(b, t_pred)
		if ab then
			local factor = clamp((rmseNow - self.opts.alphaBetaEnableRMSE)/ (self.opts.alphaBetaEnableRMSE), 0, 0.9)
			predicted = predicted:Lerp(ab, factor)
		end
	end
	if b.lastPred and b.lastPredT and newest.t > b.lastPredT then
		local dtLast = newest.t - b.lastPredT
		if dtLast > 1e-4 then
			local biasVel = (newest.pos - b.lastPred) / dtLast
			local biasFactor = clamp(b.rmse / (b.rmse + 1), 0, 1) * self.opts.maxBiasBlend
			local biasAdj = biasVel * t_pred * biasFactor
			predicted = predicted + biasAdj
		end
	end
	if self.opts.autoTune and state ~= "idle" and state ~= "teleport" then
		local target = clamp(1 / (1 + rmseNow * 0.42), 0.02, 0.65)
		local lr = self.opts.autoTuneLR
		if b.rmse and b.rmse > 8 then lr = lr * 1.5 end
		local adjustment = lr * (target - predScale)
		predScale = clamp(predScale + adjustment, 0.02, 0.85)
		b.predScale = predScale
	end
	local maxDisp = speed * (t_pred * self.opts.maxPredictionClamp + 1) + 14
	local disp = (predicted - newest.pos).Magnitude
	if disp > maxDisp then
		local dir = (predicted - newest.pos).Unit
		predicted = newest.pos + dir * maxDisp
	end
	if rmseNow > 10 or (b.inconsistent and rmseNow > 6) then
		b.failCount = b.failCount + 1
	else
		b.failCount = math.max(0, b.failCount - 1)
	end
	if b.failCount >= self.opts.failResetThreshold then
		b.samples = { newest }
		b.lastPred = nil
		b.lastPredT = nil
		b.speedEWMA = 0
		b.predScale = self.opts.predictionScale
		b.failCount = 0
		b.inconsistent = false
		local eyesPlayers = self.eyes._players
		if eyesPlayers and eyesPlayers[id] then
			eyesPlayers[id].predicted = newest.pos
			eyesPlayers[id].processorPredicted = newest.pos
		end
		b.lastPred = newest.pos
		b.lastPredT = t
		b.lastVel = Vector3.new()
		b.lastDt = dt
		self._stats.totalSamples = self._stats.totalSamples + 1
		return
	end
	local eyesPlayers = self.eyes._players
	if eyesPlayers and eyesPlayers[id] then
		eyesPlayers[id].predicted = predicted
		eyesPlayers[id].processorPredicted = predicted
	end
	b.lastPred = predicted
	b.lastPredT = t
	b.lastVel = v
	b.lastDt = dt
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
	local runner = RunService.RenderStepped or RunService.Heartbeat
	self._conns.heartbeat = runner:Connect(function(dt)
		self._lastTick = self._lastTick + dt
		local rate = math.max(1/240, (self.opts.updateRate or 1/120))
		if self._lastTick >= rate then
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
		predScale = b.predScale,
		turnRate = b.turnRate or 0,
		failCount = b.failCount or 0,
		inconsistent = b.inconsistent or false
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
