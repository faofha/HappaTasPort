-- ================================================================================================
--  CLASSIC BUILD  (HappaTAS 3 ui): makes instances from ui/classic/tree's data, as V2.38.17's builder did
--  (src/parts/p04_ui.lua at aaa21b6): a style's properties first, then the node's own; numbers for enum
--  properties become EnumItems, four equal UICorner radii become CornerRadius, and a property this Roblox
--  version doesn't have is skipped. Built once (nothing per frame).
-- ================================================================================================
local ClassicBuild = {}

local ENUM_FOR = {
	AutomaticSize = "AutomaticSize", AutomaticCanvasSize = "AutomaticSize",
	TextXAlignment = "TextXAlignment", TextYAlignment = "TextYAlignment", TextTruncate = "TextTruncate",
	ResampleMode = "ResamplerMode", ScaleType = "ScaleType",
	ElasticBehavior = "ElasticBehavior", ScrollingDirection = "ScrollingDirection",
	HorizontalScrollBarInset = "ScrollBarInset", VerticalScrollBarInset = "ScrollBarInset",
	VerticalScrollBarPosition = "VerticalScrollBarPosition",
	ApplyStrokeMode = "ApplyStrokeMode", LineJoinMode = "LineJoinMode",
	BorderStrokePosition = "BorderStrokePosition", StrokeSizingMode = "StrokeSizingMode",
	FillDirection = "FillDirection", HorizontalAlignment = "HorizontalAlignment",
	VerticalAlignment = "VerticalAlignment", SortOrder = "SortOrder",
	HorizontalFlex = "UIFlexAlignment", VerticalFlex = "UIFlexAlignment", ItemLineAlignment = "ItemLineAlignment",
}

local function setInst(inst, k, v) inst[k] = v end
local function fromValue(enumName, v) return Enum[enumName]:FromValue(v) end

local function resolve(cls, props)
	if cls == "UICorner" then
		local tl = props.TopLeftRadius
		if tl and tl == props.TopRightRadius and tl == props.BottomLeftRadius and tl == props.BottomRightRadius then
			return { CornerRadius = tl }
		end
	end
	local out = {}
	for k, v in pairs(props) do
		local enumName = ENUM_FOR[k]
		if enumName and type(v) == "number" then
			local ok, item = pcall(fromValue, enumName, v)
			v = ok and item or nil
		end
		if v ~= nil then out[k] = v end
	end
	return out
end

local function applyProps(inst, props)
	for k, v in pairs(props) do pcall(setInst, inst, k, v) end
end

-- one node and its children (styles: ClassicTree.STYLES; resolved: a cache of the styles worked out)
local function node(n, styles, resolved, path, byPath)
	local cls, name, sid, props, kids = n[1], n[2], n[3], n[4], n[5]
	local inst = Instance.new(cls)
	inst.Name = name
	local style = styles[sid]
	if style then
		local rp = resolved[sid]
		if not rp then
			rp = resolve(style[1], style[2])
			resolved[sid] = rp
		end
		applyProps(inst, rp)
	end
	if props and next(props) then applyProps(inst, resolve(cls, props)) end
	local p = (path == "") and name or (path .. "." .. name)
	if byPath and byPath[p] == nil then byPath[p] = inst end
	if kids then
		for _, k in ipairs(kids) do
			node(k, styles, resolved, p, byPath).Parent = inst
		end
	end
	return inst
end

-- every top-level node of tree into parent; byPath["MainMenu.SettingsFrame.List"] = that instance (the
-- first of a name when names repeat)
function ClassicBuild.build(tree, styles, parent)
	local byPath, resolved = {}, {}
	for _, n in ipairs(tree) do
		node(n, styles, resolved, "", byPath).Parent = parent
	end
	return parent, byPath
end

-- one node (a template: a control row, a save slot), parented by the caller
function ClassicBuild.node(n, styles)
	return node(n, styles, {}, "", nil)
end

return ClassicBuild
