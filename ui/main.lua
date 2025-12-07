local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local Light = {}
Light.__index = Light

-- Default config
local DEFAULTS = {
	Keybind = Enum.KeyCode.K,           -- toggle key (can be changed with ChangeSetting)
	PlaceholderText = "type here...",   -- textbox placeholder
	OpenOnInit = false,                 -- open when initialized
	Parent = nil,                       -- override parent (defaults to PlayerGui)
	BarSize = UDim2.new(0, 640, 0, 56),
	BarPosition = UDim2.new(0.5, -320, 0.5, -28),
	LightColor = Color3.fromRGB(240, 240, 245), -- main light gray
	AccentColor = Color3.fromRGB(220, 220, 225), -- subtle gradient
	ShowShadows = true,                 -- soft shadow layers
	MaxSuggestions = 6,                 -- maximum number of dropdown items
}

-- Create new instance
local function newInstance(config)
	local obj = setmetatable({}, Light)
	obj._config = {}
	for k,v in pairs(DEFAULTS) do obj._config[k] = v end
	if config then
		for k,v in pairs(config) do obj._config[k] = v end
	end

	-- runtime state
	obj._open = false
	obj._bindings = {}
	obj._dragging = false
	obj._dragConn = nil
	obj._inputConn = nil
	obj._keyConn = nil
	obj._textChangedConn = nil
	obj._tabConn = nil
	obj._navConn = nil
	obj.Gui = nil
	obj.Bar = nil
	obj.Input = nil
	obj.Auto = nil
	obj.Shadows = {}
	obj.Suggestions = nil
	obj._suggestionItems = {}
	obj._selectedIndex = 0
	obj._shadowOffsets = {20, 15, 10, 7, 5, 3, 2}

	-- Commands
	obj.Commands = {}

	return obj
end

-- Internal: safe parent
local function parentFor(obj)
	if obj._config.Parent then
		return obj._config.Parent
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

-- helper: find best player match from partial (case-insensitive)
local function findBestPlayerMatch(prefix)
	if not prefix or prefix == "" then return nil end
	prefix = prefix:lower()
	local exact = nil
	local starts = nil
	for _, p in ipairs(Players:GetPlayers()) do
		local name = (p.Name or ""):lower()
		local dname = (p.DisplayName or ""):lower()
		if name == prefix or dname == prefix then
			exact = p.Name
			break
		end
		if name:sub(1, #prefix) == prefix or dname:sub(1, #prefix) == prefix then
			if not starts then starts = p.Name end
		end
	end
	return exact or starts
end

-- Builds the GUI
function Light:buildGui()
	-- Avoid rebuilding
	if self.Gui then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LightController"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = parentFor(self)
	self.Gui = gui

	-- Optional soft shadows (subtle, light-appropriate)
	local shadows = {}
	local shadowOffsets = {unpack(self._shadowOffsets)}
	local shadowTransparencies = {0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65}
	if self._config.ShowShadows then
		for i = 1, #shadowOffsets do
			local offset = shadowOffsets[i]
			local shadow = Instance.new("Frame")
			shadow.Size = UDim2.new(0, self._config.BarSize.X.Offset + (offset * 2), 0, self._config.BarSize.Y.Offset + (offset * 2))
			shadow.Position = UDim2.new(self._config.BarPosition.X.Scale, self._config.BarPosition.X.Offset - offset, self._config.BarPosition.Y.Scale, self._config.BarPosition.Y.Offset - offset)
			shadow.BackgroundColor3 = Color3.fromRGB(0,0,0)
			shadow.BackgroundTransparency = math.clamp(0.95 - (i * 0.02), 0, 1)
			shadow.BorderSizePixel = 0
			shadow.ZIndex = 0
			shadow.Parent = gui

			local grad = Instance.new("UIGradient", shadow)
			grad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0,0,0))
			})
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, shadow.BackgroundTransparency),
				NumberSequenceKeypoint.new(1, 1)
			})
			Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 18 + offset)
			table.insert(shadows, shadow)
		end
	end
	self.Shadows = shadows

	-- Main bar (light gray)
	local bar = Instance.new("Frame")
	bar.Size = self._config.BarSize
	bar.Position = self._config.BarPosition
	bar.BackgroundColor3 = self._config.LightColor
	bar.BorderSizePixel = 0
	bar.ZIndex = 10
	bar.Parent = gui
	self.Bar = bar
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 18)

	-- subtle gradient
	local gradient = Instance.new("UIGradient", bar)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, self._config.LightColor),
		ColorSequenceKeypoint.new(1, self._config.AccentColor)
	})
	gradient.Rotation = 90

	-- TextBox (no prefix label)
	local input = Instance.new("TextBox", bar)
	input.Name = "LightInput"
	input.Size = UDim2.new(1, -100, 1, -16)
	input.Position = UDim2.new(0, 20, 0, 8)
	input.BackgroundTransparency = 1
	input.PlaceholderText = tostring(self._config.PlaceholderText or "")
	input.PlaceholderColor3 = Color3.fromRGB(140, 140, 145)
	input.TextColor3 = Color3.fromRGB(30, 30, 35)
	input.Font = Enum.Font.GothamSemibold
	input.TextSize = 20
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ClearTextOnFocus = false
	input.TextStrokeTransparency = 1
	input.ZIndex = 20
	input.Parent = bar
	self.Input = input

	-- Autocomplete / helper line (keeps as small hint; dropdown is the main thing)
	local auto = Instance.new("TextLabel", bar)
	auto.BackgroundTransparency = 1
	auto.Position = UDim2.new(0, 20, 1, -2)
	auto.Size = UDim2.new(1, -100, 0, 22)
	auto.Font = Enum.Font.Gotham
	auto.TextSize = 18
	auto.TextXAlignment = Enum.TextXAlignment.Left
	auto.TextColor3 = Color3.fromRGB(110, 110, 115)
	auto.Text = ""
	auto.ZIndex = 20
	self.Auto = auto

	-- SUGGESTIONS DROPDOWN (child of bar so it moves with it)
	local suggestions = Instance.new("Frame", bar)
	suggestions.Name = "Suggestions"
	suggestions.Visible = false
	suggestions.BackgroundColor3 = Color3.fromRGB(255,255,255)
	suggestions.BackgroundTransparency = 0
	suggestions.BorderSizePixel = 0
	suggestions.Size = UDim2.new(1, -40, 0, 0) -- height will expand with items
	suggestions.Position = UDim2.new(0, 20, 1, 8)
	suggestions.ZIndex = 25
	Instance.new("UICorner", suggestions).CornerRadius = UDim.new(0, 8)

	-- layout inside suggestions (store it on self so other functions can read it)
	local listLayout = Instance.new("UIListLayout", suggestions)
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	self._listLayout = listLayout

	-- padding container (store on suggestions as child; we'll read it later via FindFirstChildOfClass)
	local padding = Instance.new("UIPadding", suggestions)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)

	self.Suggestions = suggestions
	self._suggestionItems = {}
	self._selectedIndex = 0

	-- Make all shadows and bar positions respect bar position when dragging
	for idx, sh in ipairs(self.Shadows) do
		local offset = self._shadowOffsets[idx] or 5
		sh.Position = UDim2.new(self.Bar.Position.X.Scale, self.Bar.Position.X.Offset - offset, self.Bar.Position.Y.Scale, self.Bar.Position.Y.Offset - offset)
	end

	-- Capture focus on open by default
	input.ClearTextOnFocus = false
end


-- Internal: update placeholder
function Light:_applyPlaceholder()
	if self.Input then
		self.Input.PlaceholderText = tostring(self._config.PlaceholderText or "")
	end
end

-- Command API
function Light:AddCommand(name, func)
	if type(name) ~= "string" or type(func) ~= "function" then
		error("AddCommand expects (string, function)")
	end
	self.Commands[name:lower()] = func
end

function Light:RemoveCommand(name)
	if type(name) ~= "string" then return end
	self.Commands[name:lower()] = nil
end

-- Build and show suggestion items (list = { {text=..., kind="command"/"player", value=...}, ... })
function Light:_renderSuggestions(list)
	-- clear existing suggestion items (keep UIListLayout / UIPadding)
	for _, child in ipairs(self.Suggestions:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UICorner") then
			child:Destroy()
		end
	end

	self._suggestionItems = {}
	self._selectedIndex = 0

	local maxItems = math.max(0, math.min(#list, self._config.MaxSuggestions or 6))

	-- spacing from stored listLayout (fallback to 4)
	local spacing = 4
	if self._listLayout and self._listLayout.Padding then
		spacing = self._listLayout.Padding.Offset or spacing
	end

	local totalHeight = 0
	for i = 1, maxItems do
		local item = list[i]
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 28)
		btn.BackgroundTransparency = 1
		btn.Text = item.text
		btn.Font = Enum.Font.Gotham
		btn.TextSize = 16
		btn.TextColor3 = Color3.fromRGB(30,30,30)
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.AutoButtonColor = false
		btn.ZIndex = 30
		btn.LayoutOrder = i
		btn.Parent = self.Suggestions

		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

		local hoverBg = Instance.new("Frame", btn)
		hoverBg.Size = UDim2.new(1, 0, 1, 0)
		hoverBg.BackgroundColor3 = Color3.fromRGB(245,245,245)
		hoverBg.BackgroundTransparency = 1
		hoverBg.BorderSizePixel = 0
		hoverBg.ZIndex = 28

		local caption = Instance.new("TextLabel", btn)
		caption.BackgroundTransparency = 1
		caption.Size = UDim2.new(0, 80, 1, 0)
		caption.Position = UDim2.new(1, -84, 0, 0)
		caption.Font = Enum.Font.Gotham
		caption.TextSize = 12
		caption.TextColor3 = Color3.fromRGB(120,120,120)
		caption.Text = (item.kind == "player") and "player" or (item.kind == "command" and "command" or "")
		caption.TextXAlignment = Enum.TextXAlignment.Right
		caption.ZIndex = 31

		-- click behavior
		btn.MouseButton1Click:Connect(function()
			if item.kind == "command" then
				self.Input.Text = item.value .. " "
				self.Input:CaptureFocus()
				self:SuspendSuggestions()
			elseif item.kind == "player" then
				local current = tostring(self.Input.Text or "")
				local trimmed = current:match("^%s*(.-)%s*$") or ""
				local tokens = {}
				for p in trimmed:gmatch("%S+") do table.insert(tokens, p) end
				if #tokens >= 1 then
					if #tokens == 1 then
						self.Input.Text = tokens[1] .. " " .. item.value
					else
						tokens[2] = item.value
						self.Input.Text = table.concat(tokens, " ")
					end
				else
					self.Input.Text = item.value
				end
				self.Input:CaptureFocus()
				self:SuspendSuggestions()
			else
				self.Input.Text = item.value
				self.Input:CaptureFocus()
				self:SuspendSuggestions()
			end
		end)

		btn.MouseEnter:Connect(function()
			hoverBg.BackgroundTransparency = 0
			self._selectedIndex = i
			self:_highlightSelection()
		end)
		btn.MouseLeave:Connect(function()
			hoverBg.BackgroundTransparency = 1
			self._selectedIndex = 0
			self:_highlightSelection()
		end)

		table.insert(self._suggestionItems, {button = btn, data = item, bg = hoverBg})
		totalHeight = totalHeight + 28 + spacing
	end

	-- read padding offsets safely
	local paddingTop, paddingBottom = 12, 12
	local pad = self.Suggestions:FindFirstChildOfClass("UIPadding")
	if pad then
		paddingTop = (pad.PaddingTop and pad.PaddingTop.Offset) or paddingTop
		paddingBottom = (pad.PaddingBottom and pad.PaddingBottom.Offset) or paddingBottom
	end

	local height = math.max(0, (maxItems * 28) + ((maxItems - 1) * spacing) + paddingTop + paddingBottom)
	self.Suggestions.Size = UDim2.new(self.Suggestions.Size.X.Scale, self.Suggestions.Size.X.Offset, 0, height)
	self.Suggestions.Visible = (maxItems > 0)

	self._selectedIndex = 0
	self:_highlightSelection()
end

function Light:_highlightSelection()
	for i,entry in ipairs(self._suggestionItems) do
		if i == self._selectedIndex then
			entry.bg.BackgroundTransparency = 0
			entry.button.TextColor3 = Color3.fromRGB(10,10,10)
		else
			entry.bg.BackgroundTransparency = 1
			entry.button.TextColor3 = Color3.fromRGB(30,30,30)
		end
	end
end

function Light:_hideSuggestions()
	self.Suggestions.Visible = false
	self._suggestionItems = {}
	self._selectedIndex = 0
end

function Light:SuspendSuggestions()
	-- used to briefly hide suggestions after clicking to prevent immediate reopen
	self:_hideSuggestions()
end

-- Builds suggestion list based on current input and calls render
function Light:_updateSuggestions()
	if not self.Input or not self.Suggestions then return end
	local txt = tostring(self.Input.Text or "")
	local trimmed = txt:match("^%s*(.-)%s*$") or ""
	if trimmed == "" then
		self:_hideSuggestions()
		self.Auto.Text = ""
		return
	end

	local tokens = {}
	for p in trimmed:gmatch("%S+") do table.insert(tokens, p) end
	local first = tokens[1] and tokens[1]:lower() or ""

	-- If user typing first token: show commands starting with typed prefix
	if #tokens == 1 then
		local suggestions = {}
		if first ~= "" then
			for name, _ in pairs(self.Commands) do
				if name:sub(1, #first) == first then
					table.insert(suggestions, { text = name, kind = "command", value = name })
				end
			end
		end

		-- sort alphabetically and limit
		table.sort(suggestions, function(a,b) return a.text < b.text end)
		self.Auto.Text = (suggestions[1] and suggestions[1].text) or ""
		self:_renderSuggestions(suggestions)
		return
	end

	-- If typing second token: suggest player names
	if #tokens >= 2 then
		local partial = tokens[2]
		local results = {}
		local partialLower = (partial or ""):lower()
		for _,p in ipairs(Players:GetPlayers()) do
			local name = p.Name or ""
			local dname = p.DisplayName or ""
			if name:lower():sub(1, #partialLower) == partialLower or dname:lower():sub(1, #partialLower) == partialLower then
				table.insert(results, { text = name, kind = "player", value = name })
			end
		end
		table.sort(results, function(a,b) return a.text < b.text end)
		self.Auto.Text = (results[1] and (first .. " " .. results[1].text)) or ""
		self:_renderSuggestions(results)
		return
	end

	self:_hideSuggestions()
	self.Auto.Text = ""
end

-- Run a command string (returns ok, result/message)
function Light:Run(text)
	if not text then return false, "no text" end
	local tokens = {}
	for part in tostring(text):gmatch("%S+") do table.insert(tokens, part) end
	if #tokens == 0 then return false, "empty" end
	local cmdName = tokens[1]:lower()
	local cmd = self.Commands[cmdName]
	if not cmd then
		return false, ("unknown command: %s"):format(cmdName)
	end
	table.remove(tokens, 1)
	local ok, err = pcall(cmd, tokens, text)
	return ok, err
end

-- Open / show
function Light:Open()
	if not self.Gui then self:buildGui() end
	if self._open then return end
	self._open = true
	self.Bar.Visible = true
	for _, sh in ipairs(self.Shadows) do sh.Visible = true end
	if self.Input then
		self.Input:CaptureFocus()
		self.Input.Text = ""
		self.Auto.Text = ""
	end
	-- simple fade-in
	TweenService:Create(self.Bar, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { BackgroundTransparency = 0 }):Play()
end

-- Close / hide
function Light:Close()
	if not self._open then return end
	self._open = false
	-- fade-out
	local t = TweenService:Create(self.Bar, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
	t:Play()
	t.Completed:Wait()
	self.Bar.Visible = false
	for _, sh in ipairs(self.Shadows) do sh.Visible = false end
	self:_hideSuggestions()
end

function Light:Toggle()
	if self._open then self:Close() else self:Open() end
end

-- Keybind binding (ensures single binding)
function Light:_bindKey(keycode)
	-- unbind previous
	if self._keyConn then
		self._keyConn:Disconnect()
		self._keyConn = nil
	end
	if not keycode then return end

	self._keyConn = UserInputService.InputBegan:Connect(function(inp, gp)
		if gp then return end
		if inp.KeyCode == keycode then
			self:Toggle()
		end
	end)
end

-- Autocomplete update (commands and player name suggestions)
function Light:_updateAuto()
	if not self.Input or not self.Auto then return end
	local txt = self.Input.Text or ""
	local trimmed = txt:match("^%s*(.-)%s*$") or ""
	if trimmed == "" then
		self.Auto.Text = ""
		return
	end

	local tokens = {}
	for part in trimmed:gmatch("%S+") do table.insert(tokens, part) end
	local first = tokens[1] and tokens[1]:lower() or ""

	-- if typing the first token -> suggest commands (quick hint)
	if #tokens == 1 then
		if first == "" then self.Auto.Text = "" return end
		local best = nil
		for name, _ in pairs(self.Commands) do
			if name:sub(1, #first) == first then
				best = name
				break
			end
		end
		self.Auto.Text = best or ""
		return
	end

	-- if typing second token -> suggest player names
	if #tokens >= 2 then
		local partial = tokens[2]
		local match = findBestPlayerMatch(partial)
		if match then
			self.Auto.Text = first .. " " .. match
			return
		end
		self.Auto.Text = ""
		return
	end
end

-- Dragging behavior
function Light:_enableDragging()
	if not self.Bar then return end

	self.Bar.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			self._dragging = true
			local startPos = self.Bar.Position
			local startMouse = inp.Position
			local con
			con = inp.Changed:Connect(function()
				if inp.UserInputState == Enum.UserInputState.End then
					self._dragging = false
					if self._dragConn then
						self._dragConn:Disconnect()
						self._dragConn = nil
					end
					con:Disconnect()
				end
			end)
			self._dragConn = UserInputService.InputChanged:Connect(function(i)
				if self._dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
					local delta = i.Position - startMouse
					local newPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
					self.Bar.Position = newPos
					-- move shadows to keep relative offsets
					for idx, shadow in ipairs(self.Shadows) do
						local offset = self._shadowOffsets[idx] or 5
						shadow.Position = UDim2.new(newPos.X.Scale, newPos.X.Offset - offset, newPos.Y.Scale, newPos.Y.Offset - offset)
					end
				end
			end)
		end
	end)
end

-- Change a setting at runtime
-- supported keys: "Keybind" (Enum.KeyCode or string), "PlaceholderText", "OpenOnInit", "ShowShadows", "BarPosition", "BarSize", "Parent"
function Light:ChangeSetting(key, value)
	key = tostring(key)
	if key == "Keybind" then
		-- accept Enum.KeyCode or string like "M"
		local kc = value
		if type(kc) == "string" then
			-- try to look up Enum.KeyCode
			local ok, e = pcall(function() return Enum.KeyCode[kc] end)
			if ok and e then kc = e else kc = nil end
		end
		if typeof(kc) == "EnumItem" then
			self._config.Keybind = kc
			self:_bindKey(kc)
			return true
		else
			return false, "invalid Keybind value"
		end
	elseif key == "PlaceholderText" then
		self._config.PlaceholderText = tostring(value)
		self:_applyPlaceholder()
		return true
	elseif key == "OpenOnInit" then
		self._config.OpenOnInit = not not value
		return true
	elseif key == "ShowShadows" then
		self._config.ShowShadows = not not value
		-- rebuild if needed
		if self.Gui then
			self:Destroy()
			self:Init(self._config)
		end
		return true
	elseif key == "BarPosition" then
		if typeof(value) == "UDim2" then
			self._config.BarPosition = value
			if self.Bar then self.Bar.Position = value end
			return true
		else
			return false, "BarPosition must be UDim2"
		end
	elseif key == "BarSize" then
		if typeof(value) == "UDim2" then
			self._config.BarSize = value
			if self.Bar then self.Bar.Size = value end
			return true
		else
			return false, "BarSize must be UDim2"
		end
	elseif key == "Parent" then
		self._config.Parent = value
		-- If already built, move Gui
		if self.Gui and typeof(value) == "Instance" then
			self.Gui.Parent = value
		end
		return true
	else
		-- generic set
		self._config[key] = value
		return true
	end
end

function Light:GetSetting(key)
	return self._config[key]
end

-- Initializes the module instance (call from LocalScript)
-- optional config table allowed
function Light:Init(config)
	-- if already initialized, allow re-init with new config values
	if config then
		for k,v in pairs(config) do self._config[k] = v end
	end

	self:buildGui()
	self:_applyPlaceholder()
	self:_enableDragging()
	self:_bindKey(self._config.Keybind)

	-- connect FocusLost to execute commands and hide
	if self.Input and not self._inputConn then
		self._inputConn = self.Input.FocusLost:Connect(function(enter)
			if enter and self.Input.Text ~= "" then
				-- execute command text
				local ok, res = self:Run(self.Input.Text)
				-- you can handle ok/res here or choose to fire an event
				self.Input.Text = ""
				self.Auto.Text = ""
			end
			wait(0.12)
			self:Close()
		end)
	end

	-- Text change -> update autocomplete and suggestions
	if self.Input and not self._textChangedConn then
		self._textChangedConn = self.Input:GetPropertyChangedSignal("Text"):Connect(function()
			self:_updateAuto()
			self:_updateSuggestions()
		end)
	end

	-- Tab completion / extra input handling
	if not self._tabConn then
		self._tabConn = UserInputService.InputBegan:Connect(function(key, gp)
			if gp then return end
			if not self.Input or not self.Input:IsFocused() then return end
			-- Tab completion existing behavior
			if key.KeyCode == Enum.KeyCode.Tab and self.Auto and self.Auto.Text ~= "" then
				local current = self.Input.Text or ""
				local trimmed = current:match("^%s*(.-)%s*$") or ""
				-- if there's a space -> complete second token only
				if trimmed:find("%s") then
					local tokens = {}
					for part in trimmed:gmatch("%S+") do table.insert(tokens, part) end
					local first = tokens[1] and tokens[1]:lower() or ""
					local parts = {}
					for part in self.Auto.Text:gmatch("%S+") do table.insert(parts, part) end
					if #parts >= 2 then
						self.Input.Text = first .. " " .. parts[2]
						self.Auto.Text = ""
					else
						self.Input.Text = self.Auto.Text
						self.Auto.Text = ""
					end
				else
					-- no space -> complete command
					self.Input.Text = self.Auto.Text
					self.Auto.Text = ""
				end
			end
		end)
	end

	-- Keyboard navigation for suggestions (Up/Down/Enter)
	if not self._navConn then
		self._navConn = UserInputService.InputBegan:Connect(function(input, gp)
			if gp then return end
			if not self.Input or not self.Input:IsFocused() then return end
			if self.Suggestions and self.Suggestions.Visible then
				if input.KeyCode == Enum.KeyCode.Down then
					-- move down
					if #self._suggestionItems > 0 then
						self._selectedIndex = math.clamp((self._selectedIndex or 0) + 1, 1, #self._suggestionItems)
						self:_highlightSelection()
					end
				elseif input.KeyCode == Enum.KeyCode.Up then
					-- move up
					if #self._suggestionItems > 0 then
						self._selectedIndex = math.clamp((self._selectedIndex or 0) - 1, 1, #self._suggestionItems)
						self:_highlightSelection()
					end
				elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
					-- if selection exists, apply it, else run normally
					if self._selectedIndex and self._selectedIndex >= 1 and self._selectedIndex <= #self._suggestionItems then
						local chosen = self._suggestionItems[self._selectedIndex]
						if chosen and chosen.data then
							local item = chosen.data
							-- reuse click logic
							if item.kind == "command" then
								self.Input.Text = item.value .. " "
							elseif item.kind == "player" then
								local current = tostring(self.Input.Text or "")
								local trimmed = current:match("^%s*(.-)%s*$") or ""
								local tokens = {}
								for p in trimmed:gmatch("%S+") do table.insert(tokens, p) end
								if #tokens >= 1 then
									if #tokens == 1 then
										self.Input.Text = tokens[1] .. " " .. item.value
									else
										tokens[2] = item.value
										self.Input.Text = table.concat(tokens, " ")
									end
								else
									self.Input.Text = item.value
								end
							else
								self.Input.Text = item.value
							end
							self.Input:CaptureFocus()
							self:SuspendSuggestions()
							return
						end
					end

					-- otherwise execute the command if Enter pressed with no suggestion chosen
					if self.Input.Text ~= "" then
						local ok, res = self:Run(self.Input.Text)
						self.Input.Text = ""
						self.Auto.Text = ""
						self:SuspendSuggestions()
					end
				end
			else
				-- if suggestions not visible but Enter pressed, execute
				if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
					if self.Input and self.Input:IsFocused() and (self.Input.Text or "") ~= "" then
						local ok, res = self:Run(self.Input.Text)
						self.Input.Text = ""
						self.Auto.Text = ""
						self:SuspendSuggestions()
					end
				end
			end
		end)
	end

	if self._config.OpenOnInit then
		self:Open()
	else
		-- ensure hidden on start
		self.Bar.Visible = false
		for _, sh in ipairs(self.Shadows) do sh.Visible = false end
		self:_hideSuggestions()
	end

	return true
end

-- Destroy GUI and disconnect events
function Light:Destroy()
	if self._keyConn then
		self._keyConn:Disconnect()
		self._keyConn = nil
	end
	if self._dragConn then
		self._dragConn:Disconnect()
		self._dragConn = nil
	end
	if self._inputConn then
		self._inputConn:Disconnect()
		self._inputConn = nil
	end
	if self._textChangedConn then
		self._textChangedConn:Disconnect()
		self._textChangedConn = nil
	end
	if self._tabConn then
		self._tabConn:Disconnect()
		self._tabConn = nil
	end
	if self._navConn then
		self._navConn:Disconnect()
		self._navConn = nil
	end
	if self.Gui then
		self.Gui:Destroy()
		self.Gui = nil
	end
	self.Bar = nil
	self.Input = nil
	self.Auto = nil
	self.Shadows = {}
	self._open = false
	self.Commands = {}
end

-- Factory: return singleton instance bound to current LocalPlayer
local moduleInstance = newInstance()
return moduleInstance
