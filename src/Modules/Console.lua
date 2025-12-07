-- direct API bindings (your executor)
local rprint  = rconsoleprint
local rwarn   = rconsolewarn
local rerr    = rconsoleerr
local rinfo   = rconsoleinfo
local rclear  = rconsoleclear
local rname   = rconsolename

local Colors = {
	Red     = {255, 85, 85},
	Green   = {85, 255, 85},
	Blue    = {85, 170, 255},
	Yellow  = {255, 205, 85},
	Cyan    = {85, 255, 255},
	Magenta = {255, 85, 255},
	White   = {255, 255, 255},
	Grey    = {170, 170, 170},
	Orange  = {255, 140, 0},
	Lime    = {180, 255, 100}
}

local function safe(fn, ...)
	if fn then pcall(fn, ...) end
end

local function applyColor(c)
	if type(c) == "string" then c = Colors[c] end
	if type(c) == "table" then
		pcall(function() rconsolecolor(c[1], c[2], c[3]) end)
	end
end

local Console = {}
Console.__index = Console

function Console.new(name)
	local self = setmetatable({}, Console)
	self.title = tostring(name or "Console")

	-- opening console happens automatically when printing or clearing
	safe(rname, self.title)

	self.defaultColor = Colors.White
	return self
end

function Console:setTitle(t)
	self.title = tostring(t)
	safe(rname, self.title)
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
	local out = {}

	for i = 1, select("#", ...) do
		out[#out+1] = tostring(select(i, ...))
	end

	local msg = table.concat(out, " ")
	if prefix then msg = prefix .. " " .. msg end

	safe(rprint, msg)
	self:resetColor()
end

function Console:log(...) self:_write(nil, ...) end
function Console:info(...) applyColor("Blue") self:_write("INFO", ...) end
function Console:warn(...) applyColor("Yellow") self:_write("WARN", ...) end
function Console:error(...) applyColor("Red") self:_write("ERROR", ...) end
function Console:success(...) applyColor("Green") self:_write("OK", ...) end
function Console:colorLog(c, ...) applyColor(c) self:_write(nil, ...) end

return Console
