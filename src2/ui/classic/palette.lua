-- ================================================================================================
--  CLASSIC PALETTE  (HappaTAS 3 ui, Classic Look): every colour V2.38.17's Classic interface draws, the
--  setting that owns it, and how its "Auto" value follows the Main Colour. Tinted colours (V2's blues) keep
--  their hue offset from V2's button blue and scale their saturation / brightness by the Main Colour's
--  (a part brighter than the buttons that would go past white turns paler instead), so the default Main
--  Colour gives V2's colours exactly and darker parts stay darker for any Main Colour. Neutral colours
--  (black, white, greys, reds) stay V2's on Auto.
-- ================================================================================================
local Palette = {}

local rgb = Color3.fromRGB
Palette.BASE = rgb(0, 52, 129) -- (V2's button blue: the default Main Colour)

-- B = BackgroundColor3, T = TextColor3, P = PlaceholderColor3, S = a UIStroke's Color, D = BorderColor3,
-- I = ScrollBarImageColor3; runtime = painted by Classic's code while running (never registered from the tree)
local B, T, P, S, D, I = "BackgroundColor3", "TextColor3", "PlaceholderColor3", "Color", "BorderColor3", "ScrollBarImageColor3"
local function c(key, col, tinted, props, runtime)
	local set = {}
	for _, p in ipairs(props) do set[p] = true end
	return { key = key, color = col, tinted = tinted, props = set, runtime = runtime == true }
end
Palette.LIST = {
	c("classicWindow", rgb(0, 35, 73), true, { B }),
	c("classicPanel", rgb(0, 41, 91), true, { B }),
	c("classicButton", rgb(0, 52, 129), true, { B }),
	c("classicShade", rgb(0, 0, 0), false, { B }),
	c("classicScrollBar", rgb(0, 0, 0), false, { I }),
	c("classicLight", rgb(255, 255, 255), false, { B }),
	c("classicText", rgb(255, 255, 255), false, { T }),
	c("classicDarkText", rgb(27, 42, 53), false, { T }),
	c("classicLabelText", rgb(0, 0, 0), false, { T }),
	c("classicPlaceholder", rgb(178, 178, 178), false, { P }),
	c("classicSectionTitle", rgb(140, 205, 255), true, { T }, true),
	c("classicOutline", rgb(0, 141, 237), true, { S }),
	c("classicFieldOutline", rgb(0, 169, 244), true, { S }),
	c("classicDivider", rgb(0, 196, 248), true, { B, S }),
	c("classicLine", rgb(0, 77, 205), true, { B, S }),
	c("classicLightOutline", rgb(255, 255, 255), false, { S, D }),
	c("classicCancel", rgb(142, 11, 0), false, { B }),
	c("classicWarning", rgb(100, 0, 0), false, { B }),
	c("classicMergeOk", rgb(0, 80, 0), false, { B }, true),
	c("classicToggleOff", rgb(50, 50, 50), false, { B }, true),
	c("classicIconButton", rgb(163, 162, 165), false, { B }),
	c("classicSwitchOn", rgb(75, 75, 75), false, { B }, true),
	c("classicSwitchOff", rgb(255, 255, 255), false, { B }, true),
}
Palette.byKey = {}
for _, p in ipairs(Palette.LIST) do Palette.byKey[p.key] = p end

local function byte(x) return math.floor(x * 255 + 0.5) end
local function code(col) return byte(col.R) * 65536 + byte(col.G) * 256 + byte(col.B) end

-- [property][colour code] = the key that owns a colour Classic's tree draws there
local OWNER = {}
for _, p in ipairs(Palette.LIST) do
	if not p.runtime then
		for prop in pairs(p.props) do
			OWNER[prop] = OWNER[prop] or {}
			if OWNER[prop][code(p.color)] == nil then OWNER[prop][code(p.color)] = p.key end
		end
	end
end

-- the setting that owns colour `col` in property `prop` of a built part (nil: not a palette colour there)
function Palette.keyFor(prop, col)
	local t = OWNER[prop]
	return t and t[code(col)] or nil
end

function Palette.hex(col)
	return string.format("#%02X%02X%02X", byte(col.R), byte(col.G), byte(col.B))
end

-- a tinted V2 colour for Main Colour `main` (see the header)
function Palette.derive(main, v2)
	local bh, bs, bv = Palette.BASE:ToHSV()
	local mh, ms, mv = main:ToHSV()
	local h, s, v = v2:ToHSV()
	local nh = (mh + (h - bh)) % 1
	local ns = (bs > 0) and math.min(1, ms * s / bs) or 0
	local nv = (bv > 0) and (mv * v / bv) or v
	if nv > 1 then
		ns = ns / nv
		nv = 1
	end
	local out = Color3.fromHSV(nh, ns, nv)
	-- (whole 0 - 255 steps, as a colour typed in the settings would be)
	return rgb(byte(out.R), byte(out.G), byte(out.B))
end

local function fromHex(h) return Color3.fromHex(h:sub(2)) end

-- { [key] = Color3 } for every palette key, from the settings store
function Palette.resolve(settings)
	local main = fromHex(settings:get("classicMainColor"))
	local out = {}
	for _, p in ipairs(Palette.LIST) do
		local v = settings:get(p.key)
		if type(v) == "string" and v:sub(1, 1) == "#" then
			out[p.key] = fromHex(v)
		elseif p.tinted then
			out[p.key] = Palette.derive(main, p.color)
		else
			out[p.key] = p.color
		end
	end
	return out
end

return Palette
