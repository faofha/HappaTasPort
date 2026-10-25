-- ================================================================================================
--  ROOT  (HappaTAS 3 ui): the interface's one ScreenGui, "TASUserInterface". It goes where game scripts
--  can't read it: gethui(), else CoreGui; PlayerGui (where they can) only with "Allow PlayerGui Interface",
--  and then under a random name (V2's UI.Attach). An older copy's interface is removed first.
--  `layer` is the frame every window lives in; its UIScale is Interface scale. AutoLocalize is off: a Text
--  write costs ~0.06 ms with it, ~0.002 ms without (V2.38 live).
-- ================================================================================================
local Env = import("platform/env")

local Root = {}
Root.__index = Root

local NAME = "TASUserInterface"
local DISPLAY_ORDER = 10

local function hui()
	if not Env.gethui then return nil end
	local ok, h = pcall(Env.gethui)
	if ok and typeof(h) == "Instance" then return h end
	return nil
end

local function tryParent(gui, parent)
	if not parent then return false end
	local ok = pcall(function() gui.Parent = parent end)
	return ok and gui.Parent == parent
end

local function removeStale()
	for _, root in ipairs({ hui(), Env.svc("CoreGui") }) do
		pcall(function()
			for _, g in ipairs(root:GetChildren()) do
				if g.Name == NAME and g:IsA("ScreenGui") then g:Destroy() end
			end
		end)
	end
end

function Root.new(E)
	removeStale()
	local self = setmetatable({ E = E, parentName = nil, refused = false, offs = {} }, Root)
	local gui = Instance.new("ScreenGui")
	gui.Name = NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	pcall(function() gui.AutoLocalize = false end)
	pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
	pcall(function() gui.DisplayOrder = DISPLAY_ORDER end)
	self.gui = gui
	local layer = Instance.new("Frame")
	layer.Name = "Layer"
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.new(1, 0, 1, 0)
	layer.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = layer
	self.layer, self.scale = layer, scale
	self:applyScale()
	self.offs[#self.offs + 1] = E.settings:changed("interfaceScale", function() self:applyScale() end)
	if tryParent(gui, hui()) then
		self.parentName = "gethui"
	elseif tryParent(gui, Env.svc("CoreGui")) then
		self.parentName = "CoreGui"
	elseif E.settings:on("allowPlayerGuiInterface") then
		local lp = Env.svc("Players").LocalPlayer
		local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
		local http = Env.svc("HttpService")
		if http then pcall(function() gui.Name = http:GenerateGUID(false):gsub("-", ""):sub(1, 12) end) end
		if tryParent(gui, pg) then self.parentName = "PlayerGui" end
	end
	if not self.parentName then
		self.refused = true
		pcall(function() gui.Parent = nil end)
	end
	return self
end

function Root:applyScale()
	self.scale.Scale = self.E.settings:get("interfaceScale") / 100
end

function Root:setShown(on) self.gui.Enabled = on == true end

function Root:destroy()
	for _, off in ipairs(self.offs) do off() end
	self.offs = {}
	pcall(function() self.gui:Destroy() end)
end

return Root
