-- ================================================================================================
--  INTERFACE
--  The HappaTAS menus are described as data (style table + tree) and built once.
-- ================================================================================================
local UI = {}
do -- (the style / tree helpers are locals of this block: the main chunk is close to Luau's 200 register limit)
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
			{"TextLabel","Title",3,{Position=u(0,15,0,5),Size=u(0,220,0,30),Text="HappaTAS Loaded",TextSize=20}},
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
			{"TextLabel","Title",16,{Position=u(0,15,0,5),Size=u(0,370,0,30),Text="HappaTAS",TextSize=20}},
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
					HD("2UpdateLogN", "Update Log", 14),
					{"UIListLayout","UIListLayout",44,{}},
					{"Frame","5Credits",45,{Position=u(0,0,0,0),Size=u(1,0,0,90)},{
						UC,
						LV("0", " Happy_Liam/happa - Main Scripter/UI Design"),
						UL9,
						LV("2", " plusgiant5 - Tasability creator"),
						LV("1", " TestMicrowaveDinner - Scripting Help")
					}},
					HD("4CreditsN", "Credits", 14),
					HD("0ModelN", "Executor port - client side script", 14),
					{"Frame","3UpdateLog",46,{Position=u(0,0,0,0),Size=u(1,0,0,2390)},{
						LV("978", " 10/13/26 - 2.37.2"),
						LI("978_1", "   -   Tested in the real Roblox client, the bugs found fixed"),
						LI("978_2", "   -   Interface always loads, also when re-running the script"),
						LI("978_3", "   -   Client objects stay put when the game un-anchors them"),
						LI("978_4", "   -   Rebinding a key doesn't also run the old control"),
						LI("978_5", "   -   Replayed keys play their sound once, errors print once"),
						LI("978_6", "   -   2-5x less CPU per frame (auto-translate off, less work)"),
						LV("979", " 10/13/26 - 2.37.1"),
						LI("979_1", "   -   Menu key works even when the game used the key"),
						LI("979_2", "   -   Keys do nothing while typing in chat or a text box"),
						LI("979_3", "   -   Clicks on the HappaTAS menu never pause / unpause"),
						LV("980", " 10/13/26 - 2.37"),
						LI("980_1", "   -   Client objects: change signals, far fewer engine calls"),
						LI("980_2", "   -   Stats panel and playback do less work every frame"),
						LI("980_3", "   -   Smaller script: compact interface data, shared code"),
						LI("980_4", "   -   Same TAS files and behaviour as 2.36"),
						LV("981", " 10/12/26 - 2.36"),
						LI("981_1", "   -   MicroProfiler font, menus and tooltip match Roblox"),
						LI("981_2", "   -   Avg = frames on the bar, Max keeps the biggest spike"),
						LI("981_3", "   -   Detailed, Timers, Counters modes and a flame graph"),
						LI("981_4", "   -   MicroProfiler Size setting, dumps as HTML/text/CSV"),
						LI("981_5", "   -   MicroProfiler clicks fixed, text sits like Roblox's"),
						LV("982", " 10/12/26 - 2.35 (Rebuild)"),
						LI("982_1", "   -   Timed buttons saved, timer frozen while paused"),
						LI("982_2", "   -   First person camera works right after unpausing"),
						LI("982_3", "   -   Fake cursor shows up on the same frame (no gap)"),
						LI("982_4", "   -   Smooth client objects, in sync with the character"),
						LI("982_5", "   -   New MicroProfiler (Roblox look, real timings, F6)"),
						LI("982_6", "   -   File v3: saves viewport, tools, deaths, buttons"),
						LI("982_7", "   -   Settings grouped by topic, faster settings reads"),
						LI("982_8", "   -   Fixes: sounds, window guarding, unload, zoom"),
						LI("982_9", "   -   Lower CPU cost per frame while recording and testing"),
						UC,
						{"TextLabel","999",35,{Position=u(0,0,0.158824,0),Size=u(1,0,0,30),Text=" 7/13/22 - 2.0 Release (Happy_Liam -> HappaTAS)",TextSize=16}},
						LI("998_1", "  -  Script still usable in studio when API services are turned off"),
						LV("998", " 7/14/22 - 2.01"),
						LV("997", " 7/16/22 - 2.02"),
						LI("997_1", "  -  Fixed issue with the shiftlock cursor"),
						LI("997_2", "  -  Fixed issue with the \"Delete\" keybind"),
						LI("997_3", "  -  Fixed timer skipping forward after TAS is optimized"),
						LV("996", " 7/21/22 - 2.03"),
						LI("994_4", "  -  Unpause 1 works on any humanoid state except \"Landed\""),
						LI("996_1", "  -  Timers now show in minutes and seconds"),
						LI("996_2", "  -  Message on the bottom when the TAS playback is complete"),
						UL9,
						LI("996_3", "  -  You can see others move while they are testing"),
						LI("996_4", "  -  Removed manually toggling shiftlock while in test"),
						LV("995", " 7/24/22 - 2.04"),
						LI("995_1", "  -  New Setting 'Restart When Testing'"),
						LI("995_3", "  -  Fixed animations"),
						LI("995_4", "  -  Fixed transparency when testing"),
						LI("995_1", "  -  New Control 'Look Around' while paused with camera lock "),
						LV("994", " 7/25/22 - 2.05"),
						LI("994_1", "  -  Save/Load is a lot faster now"),
						LI("994_2", "  -  Fixed getting kicked by saving large files"),
						LI("994_3", "  -  Max slots increased"),
						LI("994_5", "  -  New setting 'Stats Text Size'"),
						LV("993", " 7/25/22 - 2.1"),
						LI("993_1", "  -  Added Help menu"),
						LI("993_2", "  -  A couple minor bug fixes"),
						LV("992", " 11/5/22 - 2.2"),
						LI("992_1", "  -  Mobile support"),
						LI("992_2", "  -  Playback speed controller"),
						LI("992_3", "  -  Replay matches the timer of recording (no FPS/lag abuse)"),
						LI("992_4", "  -  Fixes to animations, camera, and player transparency"),
						LI("992_5", "  -  Patched physics bug \"super bounce\""),
						LI("992_6", "  -  Discord Server (link in description of main game)"),
						LV("991", " 12/14/22 - 2.21"),
						LI("991_1", "   -   Data limit removed  : }"),
						LI("991_2", "   -   Better animations (real)"),
						LI("991_3", "   -   Fixed a couple TAS breaking bugs"),
						LV("990", " 1/2/23 - 2.22"),
						LI("990_1", "   -   Patched physics bugs and cheats"),
						LI("990_2", "   -   Fixed animations (not fake at all)"),
						LV("989", " 1/11/23 - 2.23"),
						LI("989_1", "   -   Patched boosted bounce (lied last time)"),
						LI("989_2", "   -   Fixed repeating slot IDs"),
						LI("989_3", "   -   Small adjustments/fixes for quality of life"),
						LV("988", " 9/16/25 - 2.23.1"),
						LI("988_1", "   -   Fixed saving and loading crashing (i think)"),
						LV("987", " 9/19/25 - 2.3"),
						LI("987_1", "   -   GUI Redesign/recolor"),
						LI("987_2", "   -   Public Save Slots"),
						LI("987_3", "   -   Merge TAS (refer to help)"),
						LI("987_4", "   -   Interpolate Playback Setting (refer to help)"),
						LI("987_9", "   -   Fixed TAS not loading in studio (must update HappaTAS loader)"),
						LI("987_5", "   -   Fixed save slot order/IDs (new slots only)"),
						LI("987_6", "   -   Update to character animations"),
						{"TextLabel","987_7",47,{Position=u(0,0,0,0),Size=u(1,0,0,35),Text="   -   You can jump if you unpause after you walk off a part while humanoid state is \"running\"",TextSize=12}},
						LI("987_8", "   -   Renamed \"Spectate\" mode to \"Idle\""),
						LV("986", " 10/11/25 - 2.31"),
						LI("986_1", "   -   Emotes 😛"),
						LI("986_2", "   -   Animation fixes (PLEASE dont be bad)"),
						LI("986_3", "   -   Fixed coyote frame abuse"),
						LV("985", " 07/03/26 - 2.33"),
						LI("985_1", "   -   Fixed camera zoom, NohBoard mouse, and client objects"),
						LV("984", " 10/10/26 - 2.33.1"),
						LI("984_1", "   -   Mobile DynamicThumbstick middle tracking position & size"),
						LI("984_2", "   -   Fixed first-person camera lock during pause and unpause"),
						LI("984_3", "   -   Sub-pixel cursor UV normalization for cross-resolution aiming"),
						LV("983", " 10/12/26 - 2.34 (Master Engine Update)"),
						LI("983_1", "   -   Official Roblox MicroProfiler replica (Ctrl+F6) with live TAS sync, Aggregate modes & scrubbing"),
						LI("983_2", "   -   Custom mechanical keyboard & click sound engine with dynamic pitch modulation"),
						LI("983_3", "   -   Client Object sync overhaul with EToH Kit v6.1.3 & 25-stud frustum culling"),
						LI("983_4", "   -   Button Timer & Obby Mechanism Sync (countdown doors & pressure plates)"),
						LI("983_5", "   -   Humanoid Death & Respawn recording across character respawns"),
						LI("983_6", "   -   Tool equip, unequip, activate, and deactivate recording & playback"),
						LI("983_7", "   -   Modern executor sandboxing (cloneref, gethui, syn.protect_gui, native LZ4)"),
						LI("983_8", "   -   Settings UI alignment fix and Help page documentation overhaul"),
					}},
					{"TextButton","ToggleMicroProfiler",20,{Position=u(0.25,0,0.5,0),Size=u(1,0,0,30),AnchorPoint=v2(0.5,0.5),Text="Toggle MicroProfiler",TextSize=16},{ K(21), ST(48) }},
					{"TextButton","1Model",20,{Position=u(0.25,0,0.5,0),Size=u(1,0,0,30),AnchorPoint=v2(0.5,0.5),Text="Unload HappaTAS",TextSize=16},{ K(21), ST(48) }}
				}}
			}},
			{"ScrollingFrame","HelpFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4,0)},{
				{"Frame","List",19,{Position=u(0,20,0,10),Size=u(0,360,1,-60)},{
					{"UIListLayout","UIListLayout",44,{}},
					HD("00", "What is HappaTAS?"),
					PA("01", 83, "HappaTAS is the most powerful public tool on Roblox used to make Tool Assisted Speedruns (TAS). This is the executor port: one client-side script that saves to your executor's workspace folder. The original 1.0 version was called Happy_Liam's TAS Maker."),
					PA("02", 50, "A Tool Assisted Speedrun or Tool Assisted Superplay (TAS for short) is a run of an obby that's already been created, and is not being played in real time."),
					PA("03", 75, "The controls in this tool will allow you to create a TAS, and replay it ingame. Start at the top of the list of controls and make your way down to figure out how it works! If you don't like the preset controls, you can change their keybind in the Controls menu."),
					HD("04", "Basic Controls"),
					H("05", "Idle", 84, false, {
						{ 64, "Idle is the default mode. Switching to Idle exits everything TAS related so you can play the obby like normal." } }),
					H("06", "Create", 100, false, {
						{ 34, "The create control switches you to create mode and pauses you, so you can start recording your TAS.", 49, 1.03 },
						{ 50, "Once you are in create mode, the controls below will give you further instructions on how to record gameplay." } }),
					H("07", "Unpause", 133, false, {
						{ 34, "The unpause control can be pressed while in create mode and paused." },
						{ 50, "Once you unpause, the TAS will begin recording. Any movement you do will show up in your recorded TAS unless you go back and remove it." },
						{ 33, "Exception: If you unpause the frame you jump off a ladder, you will be unpaused a frame earlier.", 53 } }),
					H("08", "Pause", 100, true, {
						{ 34, "The unpause control can be pressed while in create mode and unpaused." },
						{ 50, "Once you unpause, the TAS will stop recording. When paused, you can use other controls to remove parts of the TAS you don't want." } }),
					H("09", "Back/Forward", 140, true, {
						{ 50, "The back and forward keys can be pressed while in create mode, they will pause you if you are unpaused." },
						{ 78, "While paused, holding these keys will move you back and forward in time. You can use them to back if you mess up a jump, or want to be faster. Once you unpause, you will resume from where you moved back to." } }),
					H("10", "Test", 70, true, {
						{ 50, "Using the Test control will play the TAS that you created. Just sit back, relax, and feel free to flex on your friends as you watch your character go." } }),
					H("11", "Optimize TAS", 95, true, {
						{ 78, "Want to improve the speed of your TAS? Use the optimize control while in idle mode and the still frames will be removed. (Removes frames where the camera is positioned the same as the previous frame, and there are no new animations playing." } }),
					H("12", "Delete TAS", 38, true, {
						{ 20, "RIP all your hard work :(" } }),
					HD("13", "Advanced Controls"),
					H("14", "Back/Forward 1 Frame", 66, true, {
						{ 48, "The Back 1 Frame and Forward 1 Frame controls are the same as the Back and Forward controls, but holding them down has no effect." } }),
					H("15", "Return", 100, true, {
						{ 48, "The Return control can be used while in create mode, pressing it while unpaused will automatically pause you." },
						{ 34, "This will bring you back to the most recent frame that you unpaused at." } }),
					H("16", "Unpause 1 Frame", 165, true, {
						{ 33, "The Unpause 1 Frame control can be used while paused in create mode." },
						{ 48, "It is reccomend that you have Camera Lock (Paused) off if you are trying to control the camera while using this." },
						{ 64, "Exceptions: If you unpause the frame you jump off a ladder, you will be unpaused a frame earlier and for 2 frames. If you just landed a jump, you will be unpaused for 2 frames.", 53 } }),
					H("17", "Look Around", 142, true, {
						{ 48, "The look around control can be used while paused in create mode, with the setting Camera Lock (Paused) on." },
						{ 76, "This will allow you to unlock the camera and look, around, pressing the key again will re-lock the camera. The camera will automatically go back to it's intended position if you unpause while looking around." } }),
					HD("18", "Settings"),
					H("20", "Lock Camera (Mode)", 54, true, {
						{ 34, "Changes whether the camera can be controlled or not in the specified mode." } }),
					H("23", "Show Stats (Mode)", 54, true, {
						{ 34, "Changes whether or not the stats menu is open in the specified mode." } }),
					H("22", "Restart When Testing", 68, true, {
						{ 48, "Changes whether or not you go back to frame 1 when testing, useful to have off when you want to start from a certain frame while in create." } }),
					H("24", "Stats Text Size", 40, false, {
						{ 20, "Sets the size and text size of the stats menu." } }),
					HD("30", "Have fun :)"),
					{"Frame","Spacer",19,{Position=u(0,0,0,0),Size=u(0,0,0,100)}},
					H("21", "Playback Speed", 80, true, {
						{ 48, "Changes the speed that the TAS will be replayed in test mode. Testing stats will always show when playback speed is not 1." },
						{ 34, "Negative/Backwards breaks animations but you can still try it out" } }),
					H("19", "Interpolate Playback", 200, false, {
						{ 30, "When Interpolate Playback is off, test mode will run the TAS by playing it one frame at a time." },
						{ 75, "When Interpolate Playback is on, a timer will begin when the playback starts. The position and properties of the character are set to be inbetween the two frames that were recorded at the time of playback (this was default starting in 2.23)" },
						{ 75, "It is recommended that you always keep interpolate on, because it is more stable under varying framerates. If you keep the same framerate throughout the recording and don't lag, turning this off might make the run look more smooth or realistic." } }),
					HD("25", "Saving and Loading"),
					PA("26", 112, "In the save menu, add slots to save your TAS. Every slot is a compact .tas file inside HappaTasPort/<PlaceId>/ in your executor workspace, so slots only show up in the place they were saved in. Type in the name box to rename a slot (the file is renamed). There is no size or slot limit."),
					HD("27", "Merging a TAS"),
					PA("28", 114, "You are able to merge your TAS with one of your other saved TASes. By pressing the merge button, the TAS you load in from a save slot will load either before or after your current TAS. You will then be prompted to record a segment that stretches from the end of the first TAS to the beginning of the second TAS. The transition segment must end on the ground."),
					HD("29", "Keyboard and Mouse Inputs"),
					PA("29a", 147, "Your keys, right click, mouse wheel and mouse position are recorded together with every frame and replayed while testing, using the executor's input functions (keypress, mouse2press, mousemoveabs, mousescroll). The keys you use for the TAS menu are never recorded. Typing in a text box or clicking this menu is ignored. Keep the Roblox window focused during playback and keep your hands off the keyboard and mouse. The three Replay switches in Settings turn each part off."),
					HD("29b", "Client Objects"),
					PA("29c", 184, "Turn on 'Sync Client Objects' in Settings (off by default) to record the objects only your game client shows: moving, falling and swinging platforms, balloons, pushboxes, turret bullets, vanishers, beat blocks and other parts that move or change while you play (EToH kit objects). They are saved with the TAS and put back while testing and scrubbing. 'Smooth Client Objects' blends between recorded keyframes so they move smoothly at any FPS. Sounds, particles, lighting and GUIs are not synced."),
	                    HD("PortSettingsHeader", "Executor Port Settings"),
	                    PA("PortSettingsDescription", 225, "Show Completion Message controls the end-of-playback notice. Ignore Game Processed lets HappaTAS controls respond when Roblox marks an input as processed (the Menu key always does). No HappaTAS key does anything while you type in chat or a text box. NohBoard Cursor draws a fake cursor that stays still while the camera is locked (right click, shift lock, first person) and moves the hidden real cursor like the camera while testing. Invisible Mouse Speed scales that movement."),
					HD("FeaturesHeader", "Feature Modules & Tools"),
					H("31", "MicroProfiler", 210, true, {
						{ 48, "A copy of Roblox's MicroProfiler (F6). Time = last frame, Avg = average of the frames on the bar, Max = biggest frame (stays until a bigger one)." },
						{ 48, "Aggregate Infinite counts frames; picking it resets Max. Custom > TAS Timeline shows your TAS (green = current frame, click to jump there)." },
						{ 44, "Mode: Detailed, Timers, Counters, Frame, Hidden. [Dump] saves frames to HappaTasPort. Pause or Ctrl+P freezes it." },
						{ 48, "Hover a menu to open it, click a line to pick it. If the text sits too high or low, change Settings > MicroProfiler Text Offset (- = up)." } }),
					H("32", "Keyboard & Click Sounds", 140, true, {
						{ 48, "Custom mechanical keyboard and mouse click sound feedback. Configure volume, enable keyboard sounds, and enable click sounds in Settings." },
						{ 48, "Sound Trigger Mode lets you select when audio plays: 0 for live recording, 1 for playback replay, or 2 for both. Dynamic Pitch Variation modulates sound pitch based on typing pace and key hold time." },
						{ 24, "Sounds automatically suppress when typing in textboxes or navigating menus." } }),
					H("33", "Mouse UV Normalization", 110, true, {
						{ 48, "Normalizes cursor positions to camera viewport UV coordinates (0 to 1) after subtracting GuiService topbar insets." },
						{ 42, "Provides 1:1 cross-resolution aiming: replays on different screen resolutions or window sizes aim and click at the exact sub-pixel world location." } }),
					H("34", "Death & Respawn Recording", 110, true, {
						{ 48, "Record speedruns that use character deaths (killbricks, reset tricks, or respawn shortcuts) without crashing or resetting to Idle." },
						{ 42, "Terminal death frames are saved, and playback bridges smoothly across respawns, refreshing character and animation references on CharacterAdded." } }),
					H("35", "Tool Actions Support", 95, true, {
						{ 48, "Records and replays Tool equips, unequips, activations (clicks), and deactivations from your Character and Backpack." },
						{ 27, "Missing tools during playback are bypassed gracefully with a temporary status notice." } }),
					H("36", "Button & Obby Mechanism Sync", 135, true, {
						{ 48, "Direct integration with EToH Kit v6.1.3 button and timer mechanisms: timed switches, pressure plates, countdown doors, and disappearing segments." },
						{ 67, "Every press and release is saved with its frame. While paused the kit timer is frozen, scrubbing restores the button exactly, and testing runs the timer on the TAS clock." } }),
					H("37", "Frustum Culling & Sandboxing", 135, true, {
						{ 48, "Frustum culling filters out invisible and off-screen client objects unless within a 25-stud interaction radius, drastically reducing file size and recording lag." },
						{ 67, "Metatable sandboxing with cloneref prevents game scripts from intercepting TAS operations. UI isolation mounts via gethui/syn.protect_gui, and native LZ4 provides instant file compression." } })
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
	-- numbers -> EnumItems, 4 equal UICorner radii -> CornerRadius. A property this Roblox version
	-- doesn't have is skipped (its set fails inside pcall, an unknown enum value is dropped here).
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
	local resolved = {} -- style id -> resolved properties (worked out once, shared by every node)
	local function applyProps(inst, props)
		for k, v in pairs(props) do pcall(setInst, inst, k, v) end
	end

	local function build(node)
		local cls, name, sid, props, kids = node[1], node[2], node[3], node[4], node[5]
		local inst = Instance.new(cls)
		inst.Name = name
		local style = UI_STYLES[sid]
		if style then
			local rp = resolved[sid]
			if not rp then rp = resolve(style[1], style[2]); resolved[sid] = rp end
			applyProps(inst, rp)
		end
		if props and next(props) then applyProps(inst, resolve(cls, props)) end
		if kids then
			for _, k in ipairs(kids) do
				build(k).Parent = inst
			end
		end
		return inst
	end
	UI.BuildNode = build

	UI.Templates = {}
	for name, node in pairs(UI_TEMPLATES) do
		UI.Templates[name] = build(node)
	end
	function UI.Template(name)
		return UI.Templates[name]:Clone()
	end

	-- rows of the Settings tab, generated from SettingsTable
	local function toggleRow(def)
		return {"Frame", def.name, 34, {Size = u(1, 0, 0, 30), LayoutOrder = def.order * 2}, {
			{"UICorner", "UICorner", 5, {}},
			{"TextLabel", "N", 35, {Position = u(0, 10, 0, 0), Size = u(0.75, 0, 1, 0), Text = def.label, TextSize = 16}},
			{"TextButton", "Switch", 36, {Position = u(0.9, 0, 0.5, 0), Size = u(0, 30, 0, 15), AnchorPoint = v2(0.5, 0.5), Text = "", TextSize = 13}, {
				{"UICorner", "UICorner", 37, {}},
				{"Frame", "Switcher", 38, {Position = u(0, 0, 0.5, 0), Size = u(0, 22, 0, 22), AnchorPoint = v2(0.5, 0.5)}, {
					{"UICorner", "UICorner", 37, {}},
				}},
			}},
			{"Frame", "Border", 39, {Position = u(0, 0, 1, 0), Size = u(1, 0, 0, 1), AnchorPoint = v2(0, 1)}},
		}}
	end
	local function numberRow(def)
		local labelSize = (#def.label > 24) and 13 or 16
		return {"Frame", def.name, 34, {Size = u(1, 0, 0, 30), LayoutOrder = def.order * 2}, {
			{"UICorner", "UICorner", 5, {}},
			{"TextBox", "Input", 40, {Position = u(0.9, 0, 0.5, 0), Size = u(0.15, 0, 0.7, 0), AnchorPoint = v2(0.5, 0.5), Text = tostring(def.default), TextSize = 13, PlaceholderText = ""}, {
				{"UICorner", "UICorner", 5, {}},
				{"UIStroke", "UIStroke", 41, {}},
			}},
			{"TextLabel", "N", 35, {Position = u(0, 10, 0, 0), Size = u(0.75, 0, 1, 0), Text = def.label, TextSize = labelSize}},
			{"Frame", "Border", 39, {Position = u(0, 0, 1, 0), Size = u(1, 0, 0, 1), AnchorPoint = v2(0, 1)}},
		}}
	end
	function UI.BuildSettingsRows(list)
		local lastSection
		for _, def in ipairs(SettingsTable) do
			if def.section ~= lastSection then
				lastSection = def.section
				local h = build({"TextLabel", "Section_" .. def.section, 16, {Size = u(1, 0, 0, 28), Text = def.section, TextSize = 14, LayoutOrder = def.order * 2 - 1}})
				pcall(function() h.TextColor3 = Color3.fromRGB(140, 205, 255) end)
				h.Parent = list
			end
			local node = (def.kind == "toggle") and toggleRow(def) or numberRow(def)
			build(node).Parent = list
		end
	end

	-- AutoLocalize off: Roblox sends every new Text with letters through its automatic translation
	-- (GuiBase2d.AutoLocalize, inherited by the descendants). Measured in the live client: a Text
	-- write costs about 0.06 ms with it, 0.002 ms without, and the MicroProfiler changes texts every frame.
	local function noTranslate(sg) pcall(function() sg.AutoLocalize = false end) end

	function UI.Create()
		local gui = Instance.new("ScreenGui")
		gui.Name = "TASUserInterface"
		gui.ResetOnSpawn = false
		noTranslate(gui)
		pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Global end)
		pcall(function() gui.DisplayOrder = 0 end)
		for _, node in ipairs(UI_TREE) do
			build(node).Parent = gui
		end
		UI.BuildSettingsRows(gui.MainMenu.SettingsFrame.List)
		return gui
	end

	-- parents a ScreenGui where game scripts can't read it (gethui -> CoreGui -> PlayerGui).
	-- mayWait: when neither hidden place takes it, both are tried again a frame later before PlayerGui
	-- (gethui() can be nil for the rest of a frame, see gameCall in the bridge)
	local function tryParent(gui, parent)
		local ok = pcall(function() gui.Parent = parent end)
		return ok and gui.Parent ~= nil
	end
	function UI.Attach(gui, mayWait)
		if Env.protectgui then pcall(Env.protectgui, gui) end
		for pass = 1, mayWait and 2 or 1 do
			if pass == 2 then task.wait() end
			if Env.gethui then
				local ok, h = pcall(Env.gethui)
				if ok and typeof(h) == "Instance" and tryParent(gui, h) then
					UI.ParentName = "gethui"
					return true
				end
			end
			local core = svc("CoreGui")
			if core and tryParent(gui, core) then
				UI.ParentName = "CoreGui"
				return true
			end
		end
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
		if pg then
			-- last resort: visible to game scripts, so don't use an obvious name
			gui.Name = HttpService and HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 12) or gui.Name
			if tryParent(gui, pg) then
				UI.ParentName = "PlayerGui"
				return true
			end
		end
		return false
	end

	-- interfaces an older copy left behind: the Unload of V2.37.1 and older could lose its access to
	-- CoreGui half way (see gameCall in the bridge) and leave its windows on screen, dead
	local OWN_GUIS = { TASUserInterface = true, HappaProfiler = true, HappaCursor = true }
	function UI.RemoveStale()
		local roots = {}
		if Env.gethui then
			local ok, h = pcall(Env.gethui)
			if ok and typeof(h) == "Instance" then roots[1] = h end
		end
		roots[#roots + 1] = svc("CoreGui")
		for _, root in ipairs(roots) do
			pcall(function()
				for _, g in ipairs(root:GetChildren()) do
					if OWN_GUIS[g.Name] and g:IsA("ScreenGui") then g:Destroy() end
				end
			end)
		end
	end

	-- extra ScreenGuis (cursor, profiler) that sit above everything
	function UI.Overlay(name, displayOrder)
		local sg = Instance.new("ScreenGui")
		sg.Name = name
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
		noTranslate(sg)
		pcall(function() sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
		pcall(function() sg.DisplayOrder = displayOrder end)
		if not UI.Attach(sg) then
			sg:Destroy()
			return nil
		end
		Janitor.add(sg)
		return sg
	end
end

