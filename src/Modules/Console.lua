local _R = assert(rconsole, "~ Script doesn't support rconsole")

local function fetch(...)
	for i = 1, select("#", ...) do
		local n = select(i, ...)
		if type(_R) == "table" and _R[n] then return _R[n] end
		if _G[n] then return _G[n] end
	end
	return nil
end

local rcreate  = fetch("create","Create","rconsolecreate")
local rclear   = fetch("clear","Clear","rconsoleclear")
local rprint   = fetch("print","Print","rconsoleprint")
local rwarn    = fetch("warn","Warn","rconsolewarn")
local rerr     = fetch("err","Error","rconsoleerr","rconsoleerror")
local rcolor   = fetch("color","Color","rconsolecolor","rconsolesetcolor")
local rsettitle= fetch("settitle","SetTitle","rconsolesettitle")

local Colors = {
	Red     = {255,  85,  85},
	Green   = {85,  255,  85},
	Blue    = {85,  170, 255},
	Yellow  = {255, 205,  85},
	Cyan    = {85,  255, 255},
	Magenta = {255,  85, 255},
	White   = {255, 255, 255},
	Grey    = {170, 170, 170},
	Orange  = {255, 140,   0},
	Lime    = {180, 255, 100}
}

local function safe(fn, ...)
	if not fn then return end
	pcall(fn, ...)
end

local function applyColor(c)
	if not c then return end
	if type(c) == "string" then c = Colors[c] end
	if type(c) == "table" and #c >= 3 then
		safe(rcolor, c[1], c[2], c[3])
	end
end

local Console = {}
Console.__index = Console

function Console.new(name)
	local self = setmetatable({}, Console)
	self.title = tostring(name or "rconsole")
	if rcreate then safe(rcreate) end
	if rsettitle then safe(rsettitle, self.title) end
	self.defaultColor = Colors.White
	return self
end

function Console:setTitle(t)
	self.title = tostring(t or self.title)
	safe(rsettitle, self.title)
end

function Console:clear()
	safe(rclear)
end

function Console:setColor(c)
	applyColor(c)
end

function Console:resetColor()
	applyColor(self.defaultColor)
end

function Console:_write(prefix, ...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts+1] = tostring(select(i, ...))
	end
	local line = table.concat(parts, " ")
	if prefix then line = prefix .. " " .. line end
	safe(rprint, line)
	self:resetColor()
end

function Console:log(...) self:_write(nil, ...) end
function Console:info(...) applyColor(Colors.Blue) self:_write("INFO", ...) end
function Console:warn(...) applyColor(Colors.Yellow) self:_write("WARN", ...) end
function Console:error(...) applyColor(Colors.Red) self:_write("ERROR", ...) end
function Console:success(...) applyColor(Colors.Green) self:_write("OK", ...) end
function Console:colorLog(c, ...) applyColor(c) self:_write(nil, ...) end
function Console:colorPrefixed(c, prefix, ...) applyColor(c) self:_write(prefix, ...) end

function Console:palette(name) return Colors[name] end

return Console
