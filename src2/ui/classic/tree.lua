-- ================================================================================================
--  CLASSIC TREE  (HappaTAS 3 ui, spec 8.5): V2.38.17's interface as data, ported from src/parts/p04_ui.lua
--  (commit aaa21b6): STYLES (a style = every property of its class: a base + what differs), TREE (node =
--  { class, name, style, properties, children }) and TEMPLATES (a control row, a save slot). Changes from
--  V2.38.17: the titles carry HappaTAS 3's version; the update log holds this version's What's new list
--  (ui/win/helptext; V2's rows are in the README's version history); the Help
--  list is empty (the classic menu fills it from ui/win/helptext); the Settings list is empty (filled from
--  the settings schema). Built by ui/classic/build.
-- ================================================================================================
local CONFIG = import("config")
local HelpText = import("ui/win/helptext")

local ClassicTree = {}
do -- (the style / tree helpers are locals of this block, as in V2)
	local c  = function(r_, g, b) return Color3.fromRGB(r_, g, b) end
	local u  = UDim2.new
	local v2 = Vector2.new
	local rc = Rect.new
	local ud = UDim.new
	local function F(family, weight, style)
		return Font.new(family, Enum.FontWeight:FromValue(weight), Enum.FontStyle:FromValue(style))
	end
	-- ------------------------------------------------------------------------------------------------ UI STYLES
	-- a style = every property of its class: a base for the class + what differs from it
	local function X(base, over)
		local t = table.clone(base)
		for k, v in pairs(over) do t[k] = v end
		return t
	end
	local function CR(s, o) local r = ud(s, o) return { TopLeftRadius = r, TopRightRadius = r, BottomLeftRadius = r, BottomRightRadius = r } end
	local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"
	local G5, G7, ARIAL = F(GOTHAM, 500, 0), F(GOTHAM, 700, 0), F("rbxasset://fonts/families/LegacyArial.json", 400, 0)
	local GUI = { Active = false, AutomaticSize = 0, BackgroundColor3 = c(255, 255, 255), BackgroundTransparency = 1, BorderColor3 = c(27, 42, 53), BorderSizePixel = 1, ClipsDescendants = false, Rotation = 0 }
	local TXT = X(GUI, { FontFace = F(GOTHAM, 400, 0), RichText = false, TextColor3 = c(255, 255, 255), TextScaled = false, TextStrokeColor3 = c(0, 0, 0),
		TextStrokeTransparency = 1, TextTransparency = 0, TextTruncate = 0, TextWrapped = false, TextXAlignment = 2, TextYAlignment = 1, LineHeight = 1 })
	local BTN = X(TXT, { Active = true, AutoButtonColor = true })
	local BOX = X(TXT, { Active = true, ClearTextOnFocus = true, MultiLine = false, PlaceholderColor3 = c(178, 178, 178), ShowNativeInput = true, TextEditable = true })
	local IMG = X(GUI, { ImageColor3 = c(255, 255, 255), ImageTransparency = 0, ResampleMode = 0, ScaleType = 0, SliceCenter = rc(0, 0, 0, 0), SliceScale = 1, TileSize = u(1, 0, 1, 0) })
	local STK = { ApplyStrokeMode = 0, BorderOffset = ud(0, 0), BorderStrokePosition = 0, Color = c(0, 77, 205), Enabled = true, LineJoinMode = 0, StrokeSizingMode = 0, Thickness = 1, Transparency = 0 }
	local LST = { FillDirection = 1, HorizontalAlignment = 1, HorizontalFlex = 0, ItemLineAlignment = 0, Padding = ud(0, 0), SortOrder = 0, VerticalAlignment = 1, VerticalFlex = 0, Wraps = false }
	local UI_STYLES = {
		[1] = {"Frame", X(GUI, {BackgroundColor3=c(0,35,73),BackgroundTransparency=0.2,BorderSizePixel=0})},
		[2] = {"TextLabel", X(TXT, {FontFace=G5,TextWrapped=true,TextXAlignment=0})},
		[3] = {"TextLabel", X(TXT, {FontFace=G7,TextWrapped=true,TextXAlignment=0})},
		[4] = {"TextButton", X(BTN, {BackgroundColor3=c(0,41,91),BackgroundTransparency=0.5,BorderSizePixel=0,FontFace=F("rbxasset://fonts/families/SourceSansPro.json",400,0)})},
		[5] = {"UICorner", CR(0, 8)},
		[6] = {"UIStroke", X(STK, {ApplyStrokeMode=1,Transparency=0.5})},
		[7] = {"UIStroke", X(STK, {Color=c(0,141,237)})},
		[8] = {"Frame", X(GUI, {BackgroundColor3=c(0,35,73),BackgroundTransparency=0.2})},
		[9] = {"UIListLayout", LST},
		[10] = {"TextLabel", X(TXT, {BorderSizePixel=0,TextXAlignment=0})},
		[11] = {"TextLabel", X(TXT, {TextScaled=true,TextWrapped=true})},
		[12] = {"Folder", {}},
		[13] = {"TextButton", X(BTN, {BackgroundColor3=c(0,35,73),BackgroundTransparency=0.2,BorderColor3=c(255,255,255),BorderSizePixel=0,FontFace=G7})},
		[14] = {"ImageLabel", IMG},
		[15] = {"ImageLabel", X(IMG, {Rotation=185})},
		[16] = {"TextLabel", X(TXT, {FontFace=G7,TextWrapped=true})},
		[17] = {"UIStroke", STK},
		[18] = {"TextLabel", X(TXT, {TextWrapped=true})},
		[19] = {"Frame", GUI},
		[20] = {"TextButton", X(BTN, {BackgroundColor3=c(0,52,129),BackgroundTransparency=0.5})},
		[21] = {"UICorner", CR(0, 12)},
		[22] = {"UIStroke", X(STK, {ApplyStrokeMode=1,Color=c(255,255,255),Transparency=0.5})},
		[23] = {"TextButton", X(BTN, {BackgroundColor3=c(142,11,0),BackgroundTransparency=0.5})},
		[24] = {"TextButton", X(BTN, {Active=false,BackgroundColor3=c(100,0,0),BackgroundTransparency=0.2,ClipsDescendants=true,FontFace=ARIAL,TextColor3=c(27,42,53),TextTransparency=0.2})},
		[25] = {"TextLabel", X(TXT, {BorderSizePixel=0,FontFace=G7})},
		[26] = {"Frame", X(GUI, {BackgroundColor3=c(0,77,205),BackgroundTransparency=0,BorderSizePixel=0})},
		[27] = {"TextButton", X(BTN, {Active=false,BackgroundColor3=c(0,0,0),BorderSizePixel=0,TextWrapped=true})},
		[28] = {"TextButton", X(BTN, {Active=false,BackgroundColor3=c(0,0,0),BackgroundTransparency=0.75,BorderSizePixel=0,TextWrapped=true})},
		[29] = {"ScrollingFrame", X(GUI, {Active=true,BorderSizePixel=0,ClipsDescendants=true,AutomaticCanvasSize=0,BottomImage="rbxasset://textures/ui/Scroll/scroll-bottom.png",ElasticBehavior=0,HorizontalScrollBarInset=0,MidImage="rbxasset://textures/ui/Scroll/scroll-middle.png",ScrollBarImageColor3=c(0,0,0),ScrollBarImageTransparency=0,ScrollBarThickness=12,ScrollingDirection=4,ScrollingEnabled=true,TopImage="rbxasset://textures/ui/Scroll/scroll-top.png",VerticalScrollBarInset=0,VerticalScrollBarPosition=0})},
		[30] = {"TextLabel", TXT},
		[31] = {"Frame", X(GUI, {BackgroundColor3=c(0,41,91),BackgroundTransparency=0.2})},
		[32] = {"UIListLayout", X(LST, {SortOrder=2})},
		[33] = {"UIStroke", X(STK, {Color=c(0,169,244)})},
		[34] = {"Frame", X(GUI, {BackgroundColor3=c(0,0,0),ClipsDescendants=true})},
		[35] = {"TextLabel", X(TXT, {TextXAlignment=0})},
		[36] = {"TextButton", X(BTN, {BackgroundTransparency=0.5,TextColor3=c(0,0,0)})},
		[37] = {"UICorner", CR(100, 100)},
		[38] = {"Frame", X(GUI, {BackgroundTransparency=0})},
		[39] = {"Frame", X(GUI, {BackgroundColor3=c(0,196,248),BackgroundTransparency=0.5,BorderSizePixel=0})},
		[40] = {"TextBox", X(BOX, {BackgroundColor3=c(0,52,129),BackgroundTransparency=0.5})},
		[41] = {"UIStroke", X(STK, {ApplyStrokeMode=1,Color=c(0,169,244),Transparency=0.8})},
		[42] = {"Frame", X(GUI, {BackgroundColor3=c(0,41,91),BackgroundTransparency=0.5})},
		[43] = {"UIListLayout", X(LST, {Padding=ud(0,5),SortOrder=2})},
		[44] = {"UIListLayout", X(LST, {Padding=ud(0,5)})},
		[45] = {"Frame", X(GUI, {BackgroundColor3=c(0,0,0),BackgroundTransparency=0.75,ClipsDescendants=true})},
		[46] = {"Frame", X(GUI, {BackgroundColor3=c(0,0,0),BackgroundTransparency=0.75})},
		[47] = {"TextLabel", X(TXT, {TextWrapped=true,TextXAlignment=0})},
		[48] = {"UIStroke", X(STK, {ApplyStrokeMode=1,Color=c(0,196,248),Transparency=0.5})},
		[49] = {"TextLabel", X(TXT, {TextWrapped=true,TextXAlignment=0,TextYAlignment=0})},
		[50] = {"TextButton", X(BTN, {Active=false,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.5,FontFace=ARIAL,TextColor3=c(27,42,53),TextTransparency=0.75})},
		[51] = {"TextLabel", X(TXT, {Active=true,BackgroundTransparency=0,FontFace=ARIAL,TextColor3=c(0,0,0)})},
		[52] = {"Frame", X(GUI, {BackgroundColor3=c(0,41,91),BackgroundTransparency=0.75})},
		[53] = {"TextLabel", X(TXT, {RichText=true,TextWrapped=true,TextXAlignment=0,TextYAlignment=0})},
		[54] = {"TextButton", X(BTN, {BackgroundColor3=c(0,52,129),BackgroundTransparency=0})},
		[55] = {"Frame", X(GUI, {Active=true,BackgroundColor3=c(0,52,129),BackgroundTransparency=0})},
		[56] = {"TextButton", BTN},
		[57] = {"Frame", X(GUI, {BackgroundTransparency=0.5,BorderSizePixel=0})},
		[58] = {"ImageButton", X(IMG, {Active=true,BackgroundColor3=c(163,162,165),ScaleType=3,AutoButtonColor=true,HoverImage="",PressedImage=""})},
		[59] = {"TextLabel", X(TXT, {Active=true,TextWrapped=true,TextXAlignment=0})},
		[60] = {"TextBox", X(BOX, {BackgroundColor3=c(0,52,129),BackgroundTransparency=0.5,TextWrapped=true})},
	}
	-- ------------------------------------------------------------------------------------------------ UI TREE
	-- node = { class, name, style, properties, children }. The helpers build the nodes that repeat.
	local UC = { "UICorner", "UICorner", 5, {} }
	local UL9 = { "UIListLayout", "UIListLayout", 9, {} }
	local function K(style) return { "UICorner", "UICorner", style, {} } end
	local function ST(style) return { "UIStroke", "UIStroke", style, {} } end
	-- a stats panel row
	local function R(name, text) return { "TextLabel", name, 10, { Position = u(0, 0, 0, 0), Size = u(1, 0, 0, 18), Text = text, TextSize = 11 } } end
	-- a mobile button (position / size in screen scale)
	local function MB(name, x, y, w, h, text, size, icon)
		return { "TextButton", name, 13, { Position = u(x, 0, y, 0), Size = u(w, 0, h, 0), Visible = false, Text = text, TextSize = size or 30 }, { UC, icon } }
	end
	-- help page: heading, paragraph (indented), and a button that opens a box of paragraphs
	-- lines = { { height, text, style?, width? }, ... }
	local function HD(name, text, size)
		return { "TextLabel", name, 30, { Position = u(0.5, 0, 0, 0), Size = u(1, 0, 0, 40), AnchorPoint = v2(0.5, 0), Text = text, TextSize = size or 16 } }
	end
	local function PA(name, h, text, style, w)
		return { "TextLabel", name, style or 49, { Position = u(0.5, 0, 0, 0), Size = u(w or 1, 0, 0, h), AnchorPoint = v2(0.5, 0), Text = "      " .. text, TextSize = 14 } }
	end
	local function H(name, title, h, corner, lines)
		local inner = {}
		for i, l in ipairs(lines) do
			inner[#inner + 1] = PA(string.format("%02d", i), l[1], l[2], l[3], l[4])
			if i == 1 then inner[2] = { "UIListLayout", "UIListLayout", 32, {} } end
		end
		local box = { "Frame", "InnerBox", 19, { Position = u(0, 10, 0, 15), Size = u(1, -20, 1, -20) }, inner }
		return { "TextButton", name, 50, { Position = u(0, 0, 0, 0), Size = u(1, 0, 0, 40), Text = "", TextSize = 8 }, {
			UC,
			{ "TextLabel", "N", 47, { Position = u(0, 15, 0, 0), Size = u(0.7, 0, 1, 0), Text = title, TextSize = 20 } },
			{ "TextLabel", "Expand", 51, { Position = u(1, -10, 0.5, 0), Size = u(0, 30, 0, 30), AnchorPoint = v2(1, 0.5), ZIndex = 2, Text = "+", TextSize = 30 }, { UC } },
			{ "Frame", "Expansion", 52, { Position = u(0, 0, 1, -8), Size = u(1, 0, 0, h), Visible = false }, corner and { UC, box } or { box } },
			ST(22),
		} }
	end
	-- update log: a version line and its items
	local function LV(name, text) return { "TextLabel", name, 35, { Position = u(0, 0, 0, 0), Size = u(1, 0, 0, 30), Text = text, TextSize = 16 } } end
	local function LI(name, text) return { "TextLabel", name, 35, { Position = u(0, 0, 0, 0), Size = u(1, 0, 0, 20), Text = text, TextSize = 12 } } end
	local UI_TREE = {
		{"Frame","JoinMessage",1,{Position=u(0,10,1,150),Size=u(0,280,0,75),AnchorPoint=v2(0,1)},{
			{"TextLabel","M",2,{Position=u(0,15,0,40),Size=u(0,200,0,30),Text="M - Main Menu",TextSize=20}},
			{"TextLabel","Title",3,{Position=u(0,15,0,5),Size=u(0,220,0,30),Text="HappaTAS " .. CONFIG.VERSION .. " Loaded",TextSize=20}},
			{"TextButton","Close",4,{Position=u(1,-5,0,5),Size=u(0,30,0,30),AnchorPoint=v2(1,0),ZIndex=2,Text="X",TextSize=14},{ UC, ST(6) }},
			UC,
			{"TextLabel","FailureMessage",2,{Position=u(0,15,0,65),Size=u(0,250,0,40),Visible=false,Text="Note: your executor has no file functions, so saving to disk is disabled (recording and testing still work).",TextSize=12}},
			ST(7)
		}},
		{"Frame","IdleStats",8,{Position=u(1,-10,1,-10),Size=u(0,240,0,144),AnchorPoint=v2(1,1),Visible=false},{
			UL9,
			R("2", " Root Position: "),
			R("3", " Root Rotation:"),
			R("4", " Root Linear Velocity:"),
			R("5", " Root Angular Velocity:"),
			R("7", " Humanoid State: "),
			R("8", " Zoom:"),
			UC,
			R("1", " Frame Time: "),
			R("6", " Camera Rotation: ")
		}},
		{"Frame","TestStats",8,{Position=u(1,-10,1,-10),Size=u(0,240,0,54),AnchorPoint=v2(1,1),Visible=false},{
			UL9,
			UC,
			R("1", " Time: "),
			R("2", " Playback Speed: "),
			R("3", " Keys: "),
			R("4", " Mouse: ")
		}},
		{"TextLabel","Status",11,{Position=u(0.5,0,1,-10),Size=u(0.8,0,0,35),AnchorPoint=v2(0.5,1),Text="",TextSize=30}},
		{"Folder","Mobile",12,{},{
			{"Folder","MobileCreate",12,{},{
				MB("Pause", 0.00664428, 0.381293, 0.15625, 0.075528, "", 30, {"ImageLabel","Icon",14,{Position=u(0.357,0,0.132,0),Size=u(0.285338,0,0.7,0),Image="rbxassetid://10392248278"}}),
				MB("Back", 0.00664428, 0.237446, 0.0733061, 0.062283, "<<"),
				MB("Forward", 0.0895882, 0.237446, 0.0733061, 0.062283, ">>"),
				MB("Back1Frame", 0.0074832, 0.308445, 0.0733061, 0.062283, "<"),
				MB("Forward1Frame", 0.0905369, 0.308445, 0.0733061, 0.062283, ">"),
				MB("Unpause1Frame", 0.0900725, 0.162749, 0.0733061, 0.062283, "II 1"),
				MB("Return", 0.00748319, 0.162749, 0.0733061, 0.062283, "", 30, {"ImageLabel","Icon",15,{Position=u(0.129391,0,0.0531647,0),Size=u(0.725668,0,0.858582,0),Image="rbxassetid://6933655858"}}),
				MB("LookAround", 0.177126, 0.162749, 0.0733061, 0.062283, "", 30, {"ImageLabel","Icon",14,{Position=u(0.22074,0,0.0531647,0),Size=u(0.542971,0,0.858582,0),Image="rbxassetid://6523858394"}})
			}},
			{"Folder","MobileModes",12,{},{
				MB("Mode1Mobile", 0.0078125, 0.540233, 0.041005, 0.0639386, "1"),
				MB("Mode2Mobile", 0.065, 0.54, 0.041, 0.064, "2"),
				MB("Mode3Mobile", 0.122483, 0.538577, 0.041, 0.064, "3")
			}},
			{"Folder","MobileOptions",12,{},{
				MB("Delete", 0.174869, 0.553478, 0.111346, 0.049038, "Delete"),
				MB("Optimize", 0.174869, 0.614736, 0.111313, 0.049038, "Optimize"),
				MB("MicroProfiler", 0.174869, 0.676000, 0.111313, 0.049038, "Profiler", 24)
			}},
			MB("MenuOpener", 0.0078125, 0.468031, 0.15625, 0.0639386, "Menu"),
			MB("More", 0.17408, 0.467385, 0.111221, 0.075528, "More")
		}},
		{"Frame","Merge",8,{Position=u(0.5,0,0.5,0),Size=u(0,400,0,230),AnchorPoint=v2(0.5,0.5),Visible=false},{
			{"TextLabel","Title",16,{Position=u(0,15,0,5),Size=u(0,370,0,30),Text="Merge",TextSize=20}},
			{"TextButton","ModalFree",27,{Position=u(0,0,0,0),Size=u(0,1,0,1),Text="",Modal=true}},
			UC,
			ST(17),
			{"TextLabel","Desc",18,{Position=u(0,15,0,35),Size=u(0,370,0,100),Text="You can only merge a TAS before or after your currently loaded TAS if you are standing (idle or walking) at the endpoint where it will be merged. You will be forced to record a smooth transition inbetween segments.",TextSize=19}},
			{"Frame","Options",19,{Position=u(0,0,0,150),Size=u(1,0,0,30)},{
				{"TextButton","Before",20,{Position=u(0.25,0,0.5,0),Size=u(0.4,0,0.8,0),AnchorPoint=v2(0.5,0.5),Text="Merge Before",TextSize=16},{ K(21), ST(22) }},
				{"TextButton","After",20,{Position=u(0.75,0,0.5,0),Size=u(0.4,0,0.8,0),AnchorPoint=v2(0.5,0.5),Text="Merge After",TextSize=16},{ K(21), ST(22) }}
			}},
			{"TextButton","Cancel",23,{Position=u(0.5,0,0,200),Size=u(0.4,0,0,24),AnchorPoint=v2(0.5,0.5),Text="Cancel",TextSize=16},{ K(21), ST(22) }}
		}},
		{"Frame","CreateStats",8,{Position=u(1,-10,1,-10),Size=u(0,240,0,180),AnchorPoint=v2(1,1),Visible=false},{
			UL9,
			R("3", " Total Time:"),
			R("5", " Root Rotation:"),
			R("6", " Root Linear Velocity:"),
			R("7", " Root Angular Velocity:"),
			R("9", " Humanoid State: "),
			R("91", " Zoom:"),
			UC,
			R("2", " Frame Time:"),
			R("1", " Frame: "),
			R("4", " Root Position: "),
			R("8", " Camera Rotation: "),
			R("92", " Keys: "),
			R("93", " Mouse: ")
		}},
		{"TextButton","MergeStats",24,{Position=u(1,-10,1,-200),Size=u(0,240,0,54),AnchorPoint=v2(1,1),Visible=false,Text="",TextSize=8},{
			UL9,
			{"TextLabel","3",25,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Click here to cancel merge",TextSize=11}},
			UC,
			R("2", " Distance Required: "),
			R("1", " Current Distance: ")
		}},
		{"Frame","MainMenu",8,{Position=u(0.5,0,0.5,0),Size=u(0,400,0,400),AnchorPoint=v2(0.5,0.5),Visible=false},{
			{"TextLabel","Title",16,{Position=u(0,15,0,5),Size=u(0,370,0,30),Text="HappaTAS " .. CONFIG.VERSION,TextSize=20}},
			{"TextButton","ModalFree",27,{Position=u(0,0,0,0),Size=u(0,1,0,1),Text="",Modal=true}},
			UC,
			{"Frame","Line",26,{Position=u(0,0,0,40),Size=u(0,400,0,1)}},
			{"TextButton","ControlsToggle",27,{Position=u(0,0,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Controls",TextSize=15}},
			{"TextButton","SettingsToggle",28,{Position=u(0,80,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Settings",TextSize=15}},
			{"TextButton","SavesToggle",28,{Position=u(0,160,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Saves",TextSize=15}},
			{"ScrollingFrame","ControlsFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),CanvasSize=u(0,0,0,0)},{
				HD("Instruct", "Click on any control to change the keybind.", 14),
				{"Frame","List",31,{Position=u(0,20,0,40),Size=u(0,360,0,450)},{
					{"UIListLayout","UIListLayout",32,{}},
					UC,
					ST(33)
				}}
			}},
			{"ScrollingFrame","SettingsFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,0,890)},{
				{"Frame","List",31,{Position=u(0,20,0,20),Size=u(0,360,0,840)},{
					{"UIListLayout","UIListLayout",32,{}},
					UC,
					ST(33),
				}}
			}},
			{"ScrollingFrame","SavesFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4,0)},{
				{"Frame","YourSlots",42,{Position=u(0,20,0,20),Size=u(0,360,0,30)},{
					{"UIListLayout","UIListLayout",43,{}},
					UC,
					ST(33),
					{"Frame","Top",19,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"TextLabel","Title",30,{Position=u(0,0,0,0),Size=u(0.333,0,1,0),Text="Your Slots",TextSize=16}},
						{"TextLabel","Count",30,{Position=u(0.333,0,0,0),Size=u(0.333,0,1,0),Text="0 slots",TextSize=16}},
						{"TextButton","AddSlot",20,{Position=u(0.8325,0,0.5,0),Size=u(0.3,0,0.7,0),AnchorPoint=v2(0.5,0.5),Text="Add Slot",TextSize=16},{ K(21), ST(22) }}
					}}
				}}
			}},
			{"TextButton","HelpToggle",28,{Position=u(0,240,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Help",TextSize=15}},
			{"TextButton","MoreToggle",28,{Position=u(0,320,0,41),Size=u(0,80,0,30),ZIndex=3,Text="More",TextSize=15}},
			{"ScrollingFrame","MoreFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4.3,0)},{
				{"Frame","List",19,{Position=u(0,20,0,0),Size=u(0,360,1,-60)},{
					{"UIListLayout","UIListLayout",44,{}},
					{"Frame","5Credits",45,{Position=u(0,0,0,0),Size=u(1,0,0,108)},{
						UC,
						LV("0", " Happy_Liam/happa - Main Scripter/UI Design"),
						UL9,
						LV("2", " plusgiant5 - Tasability creator"),
						LV("1", " TestMicrowaveDinner - Scripting Help"),
						LV("3", " Skittlesuna - Playtester")
					}},
					HD("4CreditsN", "Credits", 14),
					(function() -- (V2's 3UpdateLog: a version line, then its items)
						local items = HelpText.WHATS_NEW.items
						local kids = { LV("0", " HappaTAS " .. HelpText.WHATS_NEW.version) }
						for i, item in ipairs(items) do kids[#kids + 1] = LI(tostring(i), "   -   " .. item) end
						kids[#kids + 1] = UL9
						return { "Frame", "3UpdateLog", 46, { Position = u(0, 0, 0, 0), Size = u(1, 0, 0, 30 + 20 * #items) }, kids }
					end)(),
					HD("0ModelN", "Executor port - client side script", 14),
					{"TextButton","ToggleMicroProfiler",20,{Position=u(0.25,0,0.5,0),Size=u(1,0,0,30),AnchorPoint=v2(0.5,0.5),Text="Toggle MicroProfiler",TextSize=16},{ K(21), ST(48) }},
					{"TextButton","1Model",20,{Position=u(0.25,0,0.5,0),Size=u(1,0,0,30),AnchorPoint=v2(0.5,0.5),Text="Unload HappaTAS",TextSize=16},{ K(21), ST(48) }}
				}}
			}},
			{"ScrollingFrame","HelpFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4,0)},{
				{"Frame","List",19,{Position=u(0,20,0,10),Size=u(0,360,1,-60)},{
					{"UIListLayout","UIListLayout",44,{}},
					{"Frame","Spacer",19,{Position=u(0,0,0,0),Size=u(0,0,0,100)}},
				}}
			}},
			ST(17)
		}}
	}
	local UI_TEMPLATES = {
		Control = {"Frame","ControlTemp",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
			{"TextLabel","N",30,{Position=u(0,0,0,0),Size=u(0.5,0,1,0),Text="Control",TextSize=16}},
			{"TextButton","Key",54,{Position=u(0.75,0,0.5,0),Size=u(0.4,0,0.7,0),AnchorPoint=v2(0.5,0.5),Text="Press Any Key",TextSize=16},{ K(21), ST(22) }},
			{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}}
		}},
		Slot = {"Frame","SlotTemp",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
			{"Frame","Buttons",55,{Position=u(0.75,0,0,15),Size=u(0.45,0,0,21),AnchorPoint=v2(0.5,0.5)},{
				UC,
				{"TextButton","Save",56,{Position=u(0,0,0,0),Size=u(0.4,0,1,0),Text="Save",TextSize=16}},
				{"TextButton","Load",56,{Position=u(0.4,0,0,0),Size=u(0.4,0,1,0),Text="Load",TextSize=16}},
				{"Frame","Line",57,{Position=u(0.4,0,0,0),Size=u(0,1,1,0),AnchorPoint=v2(0.5,0)}},
				{"Frame","Line",57,{Position=u(0.8,0,0,0),Size=u(0,1,1,0),AnchorPoint=v2(0.5,0)}},
				ST(22),
				{"ImageButton","Close",58,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,20),AnchorPoint=v2(0.5,0.5),Visible=false,LayoutOrder=28,ZIndex=2,Image="rbxassetid://3926307971",ImageRectOffset=v2(164,524),ImageRectSize=v2(36,36)}},
				{"ImageButton","Expand",58,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,20),AnchorPoint=v2(0.5,0.5),LayoutOrder=24,ZIndex=2,Image="rbxassetid://3926307971",ImageRectOffset=v2(204,484),ImageRectSize=v2(36,36)}}
			}},
			{"TextLabel","IDtext",59,{Position=u(0,5,0,27),Size=u(0.15,0,0,30),Text="ID: 0",TextSize=12}},
			{"Frame","Border",39,{Position=u(0,0,0,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
			{"TextBox","N",60,{Position=u(0.25,0,0,15),Size=u(0.48,0,0,21),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13,PlaceholderText="Unnamed TAS"},{ UC, ST(41) }},
			{"Frame","MoreButtons",55,{Position=u(0.75,0,0,42),Size=u(0.45,0,0,21),AnchorPoint=v2(0.5,0.5)},{
				UC,
				{"TextButton","Merge",56,{Position=u(0,0,0,0),Size=u(0.5,0,1,0),Text="Merge",TextSize=16}},
				{"TextButton","Delete",56,{Position=u(0.5,0,0,0),Size=u(0.5,0,1,0),Text="Delete",TextSize=16}},
				{"Frame","Line",57,{Position=u(0.5,0,0,0),Size=u(0,1,1,0),AnchorPoint=v2(0.5,0)}},
				ST(22)
			}}
		}},
		Z = {"Frame","Z",19,{Position=u(0,0,0,0),Size=u(0,1,0,1)}}
	}
	ClassicTree.STYLES, ClassicTree.TREE, ClassicTree.TEMPLATES = UI_STYLES, UI_TREE, UI_TEMPLATES
end

return ClassicTree
