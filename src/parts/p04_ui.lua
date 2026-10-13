-- ================================================================================================
--  INTERFACE
--  The HappaTAS menus are described as data (style table + tree) and built once.
-- ================================================================================================
local c  = function(r_, g, b) return Color3.fromRGB(r_, g, b) end
local u  = UDim2.new
local v2 = Vector2.new
local rc = Rect.new
local ud = UDim.new
local function F(family, weight, style)
	return Font.new(family, Enum.FontWeight:FromValue(weight), Enum.FontStyle:FromValue(style))
end
-- ------------------------------------------------------------------------------------------------ UI STYLES
local UI_STYLES = {
	[1] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,35,73),BackgroundTransparency=0.2,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0}},
	[2] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",500,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[3] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",700,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[4] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/SourceSansPro.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[5] = {"UICorner", {TopLeftRadius=ud(0,8),TopRightRadius=ud(0,8),BottomLeftRadius=ud(0,8),BottomRightRadius=ud(0,8)}},
	[6] = {"UIStroke", {ApplyStrokeMode=1,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,77,205),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0.5}},
	[7] = {"UIStroke", {ApplyStrokeMode=0,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,141,237),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0}},
	[8] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,35,73),BackgroundTransparency=0.2,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[9] = {"UIListLayout", {FillDirection=1,HorizontalAlignment=1,HorizontalFlex=0,ItemLineAlignment=0,Padding=ud(0,0),SortOrder=0,VerticalAlignment=1,VerticalFlex=0,Wraps=false}},
	[10] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[11] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=true,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[12] = {"Folder", {}},
	[13] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,35,73),BackgroundTransparency=0.2,BorderColor3=c(255,255,255),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",700,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[14] = {"ImageLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,ImageColor3=c(255,255,255),ImageTransparency=0,ResampleMode=0,ScaleType=0,SliceCenter=rc(0,0,0,0),SliceScale=1,TileSize=u(1,0,1,0)}},
	[15] = {"ImageLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=185,ImageColor3=c(255,255,255),ImageTransparency=0,ResampleMode=0,ScaleType=0,SliceCenter=rc(0,0,0,0),SliceScale=1,TileSize=u(1,0,1,0)}},
	[16] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",700,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[17] = {"UIStroke", {ApplyStrokeMode=0,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,77,205),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0}},
	[18] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[19] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[20] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[21] = {"UICorner", {TopLeftRadius=ud(0,12),TopRightRadius=ud(0,12),BottomLeftRadius=ud(0,12),BottomRightRadius=ud(0,12)}},
	[22] = {"UIStroke", {ApplyStrokeMode=1,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(255,255,255),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0.5}},
	[23] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(142,11,0),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[24] = {"TextButton", {Active=false,AutomaticSize=0,BackgroundColor3=c(100,0,0),BackgroundTransparency=0.2,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=true,Rotation=0,FontFace=F("rbxasset://fonts/families/LegacyArial.json",400,0),RichText=false,TextColor3=c(27,42,53),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0.2,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[25] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",700,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[26] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,77,205),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0}},
	[27] = {"TextButton", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[28] = {"TextButton", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=0.75,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[29] = {"ScrollingFrame", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=true,Rotation=0,AutomaticCanvasSize=0,BottomImage="rbxasset://textures/ui/Scroll/scroll-bottom.png",ElasticBehavior=0,HorizontalScrollBarInset=0,MidImage="rbxasset://textures/ui/Scroll/scroll-middle.png",ScrollBarImageColor3=c(0,0,0),ScrollBarImageTransparency=0,ScrollBarThickness=12,ScrollingDirection=4,ScrollingEnabled=true,TopImage="rbxasset://textures/ui/Scroll/scroll-top.png",VerticalScrollBarInset=0,VerticalScrollBarPosition=0}},
	[30] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[31] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.2,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[32] = {"UIListLayout", {FillDirection=1,HorizontalAlignment=1,HorizontalFlex=0,ItemLineAlignment=0,Padding=ud(0,0),SortOrder=2,VerticalAlignment=1,VerticalFlex=0,Wraps=false}},
	[33] = {"UIStroke", {ApplyStrokeMode=0,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,169,244),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0}},
	[34] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=true,Rotation=0}},
	[35] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[36] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(0,0,0),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[37] = {"UICorner", {TopLeftRadius=ud(100,100),TopRightRadius=ud(100,100),BottomLeftRadius=ud(100,100),BottomRightRadius=ud(100,100)}},
	[38] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[39] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,196,248),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0}},
	[40] = {"TextBox", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,ClearTextOnFocus=true,MultiLine=false,PlaceholderColor3=c(178,178,178),ShowNativeInput=true,TextEditable=true}},
	[41] = {"UIStroke", {ApplyStrokeMode=1,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,169,244),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0.8}},
	[42] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[43] = {"UIListLayout", {FillDirection=1,HorizontalAlignment=1,HorizontalFlex=0,ItemLineAlignment=0,Padding=ud(0,5),SortOrder=2,VerticalAlignment=1,VerticalFlex=0,Wraps=false}},
	[44] = {"UIListLayout", {FillDirection=1,HorizontalAlignment=1,HorizontalFlex=0,ItemLineAlignment=0,Padding=ud(0,5),SortOrder=0,VerticalAlignment=1,VerticalFlex=0,Wraps=false}},
	[45] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=0.75,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=true,Rotation=0}},
	[46] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,0,0),BackgroundTransparency=0.75,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[47] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[48] = {"UIStroke", {ApplyStrokeMode=1,BorderOffset=ud(0,0),BorderStrokePosition=0,Color=c(0,196,248),Enabled=true,LineJoinMode=0,StrokeSizingMode=0,Thickness=1,Transparency=0.5}},
	[49] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=0,LineHeight=1}},
	[50] = {"TextButton", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/LegacyArial.json",400,0),RichText=false,TextColor3=c(27,42,53),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0.75,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[51] = {"TextLabel", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/LegacyArial.json",400,0),RichText=false,TextColor3=c(0,0,0),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1}},
	[52] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(0,41,91),BackgroundTransparency=0.75,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[53] = {"TextLabel", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=true,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=0,LineHeight=1}},
	[54] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[55] = {"Frame", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0}},
	[56] = {"TextButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=false,TextXAlignment=2,TextYAlignment=1,LineHeight=1,AutoButtonColor=true}},
	[57] = {"Frame", {Active=false,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=0,ClipsDescendants=false,Rotation=0}},
	[58] = {"ImageButton", {Active=true,AutomaticSize=0,BackgroundColor3=c(163,162,165),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,ImageColor3=c(255,255,255),ImageTransparency=0,ResampleMode=0,ScaleType=3,SliceCenter=rc(0,0,0,0),SliceScale=1,TileSize=u(1,0,1,0),AutoButtonColor=true,HoverImage="",PressedImage=""}},
	[59] = {"TextLabel", {Active=true,AutomaticSize=0,BackgroundColor3=c(255,255,255),BackgroundTransparency=1,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=0,TextYAlignment=1,LineHeight=1}},
	[60] = {"TextBox", {Active=true,AutomaticSize=0,BackgroundColor3=c(0,52,129),BackgroundTransparency=0.5,BorderColor3=c(27,42,53),BorderSizePixel=1,ClipsDescendants=false,Rotation=0,FontFace=F("rbxasset://fonts/families/GothamSSm.json",400,0),RichText=false,TextColor3=c(255,255,255),TextScaled=false,TextStrokeColor3=c(0,0,0),TextStrokeTransparency=1,TextTransparency=0,TextTruncate=0,TextWrapped=true,TextXAlignment=2,TextYAlignment=1,LineHeight=1,ClearTextOnFocus=true,MultiLine=false,PlaceholderColor3=c(178,178,178),ShowNativeInput=true,TextEditable=true}}
}
-- ------------------------------------------------------------------------------------------------ UI TREE
local UI_TREE = {
		{"Frame","JoinMessage",1,{Position=u(0,10,1,150),Size=u(0,280,0,75),AnchorPoint=v2(0,1)},{
			{"TextLabel","M",2,{Position=u(0,15,0,40),Size=u(0,200,0,30),Text="M - Main Menu",TextSize=20}},
			{"TextLabel","Title",3,{Position=u(0,15,0,5),Size=u(0,220,0,30),Text="HappaTAS Loaded",TextSize=20}},
			{"TextButton","Close",4,{Position=u(1,-5,0,5),Size=u(0,30,0,30),AnchorPoint=v2(1,0),ZIndex=2,Text="X",TextSize=14},{
				{"UICorner","UICorner",5,{}},
				{"UIStroke","UIStroke",6,{}}
			}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","FailureMessage",2,{Position=u(0,15,0,65),Size=u(0,250,0,40),Visible=false,Text="Note: your executor has no file functions, so saving to disk is disabled (recording and testing still work).",TextSize=12}},
			{"UIStroke","UIStroke",7,{}}
		}},
		{"Frame","IdleStats",8,{Position=u(1,-10,1,-10),Size=u(0,240,0,144),AnchorPoint=v2(1,1),Visible=false},{
			{"UIListLayout","UIListLayout",9,{}},
			{"TextLabel","2",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Position: ",TextSize=11}},
			{"TextLabel","3",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Rotation:",TextSize=11}},
			{"TextLabel","4",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Linear Velocity:",TextSize=11}},
			{"TextLabel","5",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Angular Velocity:",TextSize=11}},
			{"TextLabel","7",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Humanoid State: ",TextSize=11}},
			{"TextLabel","8",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Zoom:",TextSize=11}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","1",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Frame Time: ",TextSize=11}},
			{"TextLabel","6",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Camera Rotation: ",TextSize=11}}
		}},
		{"Frame","TestStats",8,{Position=u(1,-10,1,-10),Size=u(0,240,0,54),AnchorPoint=v2(1,1),Visible=false},{
			{"UIListLayout","UIListLayout",9,{}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","1",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Time: ",TextSize=11}},
			{"TextLabel","2",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Playback Speed: ",TextSize=11}},
			{"TextLabel","3",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Keys: ",TextSize=11}},
			{"TextLabel","4",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Mouse: ",TextSize=11}}
		}},
		{"TextLabel","Status",11,{Position=u(0.5,0,1,-10),Size=u(0.8,0,0,35),AnchorPoint=v2(0.5,1),Text="",TextSize=30}},
		{"Folder","Mobile",12,{},{
			{"Folder","MobileCreate",12,{},{
				{"TextButton","Pause",13,{Position=u(0.00664428,0,0.381293,0),Size=u(0.15625,0,0.075528,0),Visible=false,Text="",TextSize=30},{
					{"UICorner","UICorner",5,{}},
					{"ImageLabel","Icon",14,{Position=u(0.357,0,0.132,0),Size=u(0.285338,0,0.7,0),Image="rbxassetid://10392248278"}}
				}},
				{"TextButton","Back",13,{Position=u(0.00664428,0,0.237446,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="<<",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Forward",13,{Position=u(0.0895882,0,0.237446,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text=">>",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Back1Frame",13,{Position=u(0.0074832,0,0.308445,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="<",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Forward1Frame",13,{Position=u(0.0905369,0,0.308445,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text=">",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Unpause1Frame",13,{Position=u(0.0900725,0,0.162749,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="II 1",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Return",13,{Position=u(0.00748319,0,0.162749,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="",TextSize=30},{
					{"UICorner","UICorner",5,{}},
					{"ImageLabel","Icon",15,{Position=u(0.129391,0,0.0531647,0),Size=u(0.725668,0,0.858582,0),Image="rbxassetid://6933655858"}}
				}},
				{"TextButton","LookAround",13,{Position=u(0.177126,0,0.162749,0),Size=u(0.0733061,0,0.062283,0),Visible=false,Text="",TextSize=30},{
					{"UICorner","UICorner",5,{}},
					{"ImageLabel","Icon",14,{Position=u(0.22074,0,0.0531647,0),Size=u(0.542971,0,0.858582,0),Image="rbxassetid://6523858394"}}
				}}
			}},
			{"Folder","MobileModes",12,{},{
				{"TextButton","Mode1Mobile",13,{Position=u(0.0078125,0,0.540233,0),Size=u(0.041005,0,0.0639386,0),Visible=false,Text="1",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Mode2Mobile",13,{Position=u(0.065,0,0.54,0),Size=u(0.041,0,0.064,0),Visible=false,Text="2",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Mode3Mobile",13,{Position=u(0.122483,0,0.538577,0),Size=u(0.041,0,0.064,0),Visible=false,Text="3",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}}
			}},
			{"Folder","MobileOptions",12,{},{
				{"TextButton","Delete",13,{Position=u(0.174869,0,0.553478,0),Size=u(0.111346,0,0.049038,0),Visible=false,Text="Delete",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","Optimize",13,{Position=u(0.174869,0,0.614736,0),Size=u(0.111313,0,0.049038,0),Visible=false,Text="Optimize",TextSize=30},{
					{"UICorner","UICorner",5,{}}
				}},
				{"TextButton","MicroProfiler",13,{Position=u(0.174869,0,0.676000,0),Size=u(0.111313,0,0.049038,0),Visible=false,Text="Profiler",TextSize=24},{
					{"UICorner","UICorner",5,{}}
				}}
			}},
			{"TextButton","MenuOpener",13,{Position=u(0.0078125,0,0.468031,0),Size=u(0.15625,0,0.0639386,0),Visible=false,Text="Menu",TextSize=30},{
				{"UICorner","UICorner",5,{}}
			}},
			{"TextButton","More",13,{Position=u(0.17408,0,0.467385,0),Size=u(0.111221,0,0.075528,0),Visible=false,Text="More",TextSize=30},{
				{"UICorner","UICorner",5,{}}
			}}
		}},
		{"Frame","Merge",8,{Position=u(0.5,0,0.5,0),Size=u(0,400,0,230),AnchorPoint=v2(0.5,0.5),Visible=false},{
			{"TextLabel","Title",16,{Position=u(0,15,0,5),Size=u(0,370,0,30),Text="Merge",TextSize=20}},
			{"TextButton","ModalFree",27,{Position=u(0,0,0,0),Size=u(0,1,0,1),Text="",Modal=true}},
			{"UICorner","UICorner",5,{}},
			{"UIStroke","UIStroke",17,{}},
			{"TextLabel","Desc",18,{Position=u(0,15,0,35),Size=u(0,370,0,100),Text="You can only merge a TAS before or after your currently loaded TAS if you are standing (idle or walking) at the endpoint where it will be merged. You will be forced to record a smooth transition inbetween segments.",TextSize=19}},
			{"Frame","Options",19,{Position=u(0,0,0,150),Size=u(1,0,0,30)},{
				{"TextButton","Before",20,{Position=u(0.25,0,0.5,0),Size=u(0.4,0,0.8,0),AnchorPoint=v2(0.5,0.5),Text="Merge Before",TextSize=16},{
					{"UICorner","UICorner",21,{}},
					{"UIStroke","UIStroke",22,{}}
				}},
				{"TextButton","After",20,{Position=u(0.75,0,0.5,0),Size=u(0.4,0,0.8,0),AnchorPoint=v2(0.5,0.5),Text="Merge After",TextSize=16},{
					{"UICorner","UICorner",21,{}},
					{"UIStroke","UIStroke",22,{}}
				}}
			}},
			{"TextButton","Cancel",23,{Position=u(0.5,0,0,200),Size=u(0.4,0,0,24),AnchorPoint=v2(0.5,0.5),Text="Cancel",TextSize=16},{
				{"UICorner","UICorner",21,{}},
				{"UIStroke","UIStroke",22,{}}
			}}
		}},
		{"Frame","CreateStats",8,{Position=u(1,-10,1,-10),Size=u(0,240,0,180),AnchorPoint=v2(1,1),Visible=false},{
			{"UIListLayout","UIListLayout",9,{}},
			{"TextLabel","3",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Total Time:",TextSize=11}},
			{"TextLabel","5",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Rotation:",TextSize=11}},
			{"TextLabel","6",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Linear Velocity:",TextSize=11}},
			{"TextLabel","7",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Angular Velocity:",TextSize=11}},
			{"TextLabel","9",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Humanoid State: ",TextSize=11}},
			{"TextLabel","91",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Zoom:",TextSize=11}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","2",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Frame Time:",TextSize=11}},
			{"TextLabel","1",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Frame: ",TextSize=11}},
			{"TextLabel","4",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Root Position: ",TextSize=11}},
			{"TextLabel","8",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Camera Rotation: ",TextSize=11}},
			{"TextLabel","92",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Keys: ",TextSize=11}},
			{"TextLabel","93",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Mouse: ",TextSize=11}}
		}},
		{"TextButton","MergeStats",24,{Position=u(1,-10,1,-200),Size=u(0,240,0,54),AnchorPoint=v2(1,1),Visible=false,Text="",TextSize=8},{
			{"UIListLayout","UIListLayout",9,{}},
			{"TextLabel","3",25,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Click here to cancel merge",TextSize=11}},
			{"UICorner","UICorner",5,{}},
			{"TextLabel","2",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Distance Required: ",TextSize=11}},
			{"TextLabel","1",10,{Position=u(0,0,0,0),Size=u(1,0,0,18),Text=" Current Distance: ",TextSize=11}}
		}},
		{"Frame","MainMenu",8,{Position=u(0.5,0,0.5,0),Size=u(0,400,0,400),AnchorPoint=v2(0.5,0.5),Visible=false},{
			{"TextLabel","Title",16,{Position=u(0,15,0,5),Size=u(0,370,0,30),Text="HappaTAS",TextSize=20}},
			{"TextButton","ModalFree",27,{Position=u(0,0,0,0),Size=u(0,1,0,1),Text="",Modal=true}},
			{"UICorner","UICorner",5,{}},
			{"Frame","Line",26,{Position=u(0,0,0,40),Size=u(0,400,0,1)}},
			{"TextButton","ControlsToggle",27,{Position=u(0,0,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Controls",TextSize=15}},
			{"TextButton","SettingsToggle",28,{Position=u(0,80,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Settings",TextSize=15}},
			{"TextButton","SavesToggle",28,{Position=u(0,160,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Saves",TextSize=15}},
			{"ScrollingFrame","ControlsFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),CanvasSize=u(0,0,0,0)},{
				{"TextLabel","Instruct",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Click on any control to change the keybind.",TextSize=14}},
				{"Frame","List",31,{Position=u(0,20,0,40),Size=u(0,360,0,450)},{
					{"UIListLayout","UIListLayout",32,{}},
					{"UICorner","UICorner",5,{}},
					{"UIStroke","UIStroke",33,{}}
				}}
			}},
			{"ScrollingFrame","SettingsFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,0,890)},{
				{"Frame","List",31,{Position=u(0,20,0,20),Size=u(0,360,0,840)},{
					{"UIListLayout","UIListLayout",32,{}},
					{"UICorner","UICorner",5,{}},
					{"UIStroke","UIStroke",33,{}},
				}}
			}},
			{"ScrollingFrame","SavesFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4,0)},{
				{"Frame","YourSlots",42,{Position=u(0,20,0,20),Size=u(0,360,0,30)},{
					{"UIListLayout","UIListLayout",43,{}},
					{"UICorner","UICorner",5,{}},
					{"UIStroke","UIStroke",33,{}},
					{"Frame","Top",19,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
						{"TextLabel","Title",30,{Position=u(0,0,0,0),Size=u(0.333,0,1,0),Text="Your Slots",TextSize=16}},
						{"TextLabel","Count",30,{Position=u(0.333,0,0,0),Size=u(0.333,0,1,0),Text="0 slots",TextSize=16}},
						{"TextButton","AddSlot",20,{Position=u(0.8325,0,0.5,0),Size=u(0.3,0,0.7,0),AnchorPoint=v2(0.5,0.5),Text="Add Slot",TextSize=16},{
							{"UICorner","UICorner",21,{}},
							{"UIStroke","UIStroke",22,{}}
						}}
					}}
				}}
			}},
			{"TextButton","HelpToggle",28,{Position=u(0,240,0,41),Size=u(0,80,0,30),ZIndex=3,Text="Help",TextSize=15}},
			{"TextButton","MoreToggle",28,{Position=u(0,320,0,41),Size=u(0,80,0,30),ZIndex=3,Text="More",TextSize=15}},
			{"ScrollingFrame","MoreFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4.3,0)},{
				{"Frame","List",19,{Position=u(0,20,0,0),Size=u(0,360,1,-60)},{
					{"TextLabel","2UpdateLogN",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Update Log",TextSize=14}},
					{"UIListLayout","UIListLayout",44,{}},
					{"Frame","5Credits",45,{Position=u(0,0,0,0),Size=u(1,0,0,90)},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","0",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" Happy_Liam/happa - Main Scripter/UI Design",TextSize=16}},
						{"UIListLayout","UIListLayout",9,{}},
						{"TextLabel","2",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" plusgiant5 - Tasability creator",TextSize=16}},
						{"TextLabel","1",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" TestMicrowaveDinner - Scripting Help",TextSize=16}}
					}},
					{"TextLabel","4CreditsN",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Credits",TextSize=14}},
					{"TextLabel","0ModelN",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Executor port - client side script",TextSize=14}},
					{"Frame","3UpdateLog",46,{Position=u(0,0,0,0),Size=u(1,0,0,2160)},{
							{"TextLabel","981",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 10/12/26 - 2.36",TextSize=16}},
							{"TextLabel","981_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   MicroProfiler font, menus and tooltip match Roblox",TextSize=12}},
							{"TextLabel","981_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Avg = frames on the bar, Max keeps the biggest spike",TextSize=12}},
							{"TextLabel","981_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Detailed, Timers, Counters modes and a flame graph",TextSize=12}},
							{"TextLabel","981_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   MicroProfiler Size setting, dumps as HTML/text/CSV",TextSize=12}},
							{"TextLabel","981_5",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   MicroProfiler clicks fixed, text sits like Roblox's",TextSize=12}},
							{"TextLabel","982",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 10/12/26 - 2.35 (Rebuild)",TextSize=16}},
							{"TextLabel","982_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Timed buttons saved, timer frozen while paused",TextSize=12}},
							{"TextLabel","982_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   First person camera works right after unpausing",TextSize=12}},
							{"TextLabel","982_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fake cursor shows up on the same frame (no gap)",TextSize=12}},
							{"TextLabel","982_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Smooth client objects, in sync with the character",TextSize=12}},
							{"TextLabel","982_5",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   New MicroProfiler (Roblox look, real timings, F6)",TextSize=12}},
							{"TextLabel","982_6",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   File v3: saves viewport, tools, deaths, buttons",TextSize=12}},
							{"TextLabel","982_7",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Settings grouped by topic, faster settings reads",TextSize=12}},
							{"TextLabel","982_8",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixes: sounds, window guarding, unload, zoom",TextSize=12}},
							{"TextLabel","982_9",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Lower CPU cost per frame while recording and testing",TextSize=12}},
						{"UICorner","UICorner",5,{}},
						{"TextLabel","999",35,{Position=u(0,0,0.158824,0),Size=u(1,0,0,30),Text=" 7/13/22 - 2.0 Release (Happy_Liam -> HappaTAS)",TextSize=16}},
						{"TextLabel","998_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Script still usable in studio when API services are turned off",TextSize=12}},
						{"TextLabel","998",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/14/22 - 2.01",TextSize=16}},
						{"TextLabel","997",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/16/22 - 2.02",TextSize=16}},
						{"TextLabel","997_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed issue with the shiftlock cursor",TextSize=12}},
						{"TextLabel","997_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed issue with the \"Delete\" keybind",TextSize=12}},
						{"TextLabel","997_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed timer skipping forward after TAS is optimized",TextSize=12}},
						{"TextLabel","996",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/21/22 - 2.03",TextSize=16}},
						{"TextLabel","994_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Unpause 1 works on any humanoid state except \"Landed\"",TextSize=12}},
						{"TextLabel","996_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Timers now show in minutes and seconds",TextSize=12}},
						{"TextLabel","996_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Message on the bottom when the TAS playback is complete",TextSize=12}},
						{"UIListLayout","UIListLayout",9,{}},
						{"TextLabel","996_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  You can see others move while they are testing",TextSize=12}},
						{"TextLabel","996_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Removed manually toggling shiftlock while in test",TextSize=12}},
						{"TextLabel","995",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/24/22 - 2.04",TextSize=16}},
						{"TextLabel","995_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  New Setting 'Restart When Testing'",TextSize=12}},
						{"TextLabel","995_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed animations",TextSize=12}},
						{"TextLabel","995_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed transparency when testing",TextSize=12}},
						{"TextLabel","995_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  New Control 'Look Around' while paused with camera lock ",TextSize=12}},
						{"TextLabel","994",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/25/22 - 2.05",TextSize=16}},
						{"TextLabel","994_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Save/Load is a lot faster now",TextSize=12}},
						{"TextLabel","994_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixed getting kicked by saving large files",TextSize=12}},
						{"TextLabel","994_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Max slots increased",TextSize=12}},
						{"TextLabel","994_5",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  New setting 'Stats Text Size'",TextSize=12}},
						{"TextLabel","993",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 7/25/22 - 2.1",TextSize=16}},
						{"TextLabel","993_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Added Help menu",TextSize=12}},
						{"TextLabel","993_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  A couple minor bug fixes",TextSize=12}},
						{"TextLabel","992",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 11/5/22 - 2.2",TextSize=16}},
						{"TextLabel","992_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Mobile support",TextSize=12}},
						{"TextLabel","992_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Playback speed controller",TextSize=12}},
						{"TextLabel","992_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Replay matches the timer of recording (no FPS/lag abuse)",TextSize=12}},
						{"TextLabel","992_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Fixes to animations, camera, and player transparency",TextSize=12}},
						{"TextLabel","992_5",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Patched physics bug \"super bounce\"",TextSize=12}},
						{"TextLabel","992_6",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="  -  Discord Server (link in description of main game)",TextSize=12}},
						{"TextLabel","991",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 12/14/22 - 2.21",TextSize=16}},
						{"TextLabel","991_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Data limit removed  : }",TextSize=12}},
						{"TextLabel","991_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Better animations (real)",TextSize=12}},
						{"TextLabel","991_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed a couple TAS breaking bugs",TextSize=12}},
						{"TextLabel","990",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 1/2/23 - 2.22",TextSize=16}},
						{"TextLabel","990_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Patched physics bugs and cheats",TextSize=12}},
						{"TextLabel","990_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed animations (not fake at all)",TextSize=12}},
						{"TextLabel","989",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 1/11/23 - 2.23",TextSize=16}},
						{"TextLabel","989_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Patched boosted bounce (lied last time)",TextSize=12}},
						{"TextLabel","989_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed repeating slot IDs",TextSize=12}},
						{"TextLabel","989_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Small adjustments/fixes for quality of life",TextSize=12}},
						{"TextLabel","988",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 9/16/25 - 2.23.1",TextSize=16}},
						{"TextLabel","988_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed saving and loading crashing (i think)",TextSize=12}},
						{"TextLabel","987",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 9/19/25 - 2.3",TextSize=16}},
						{"TextLabel","987_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   GUI Redesign/recolor",TextSize=12}},
						{"TextLabel","987_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Public Save Slots",TextSize=12}},
						{"TextLabel","987_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Merge TAS (refer to help)",TextSize=12}},
						{"TextLabel","987_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Interpolate Playback Setting (refer to help)",TextSize=12}},
						{"TextLabel","987_9",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed TAS not loading in studio (must update HappaTAS loader)",TextSize=12}},
						{"TextLabel","987_5",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed save slot order/IDs (new slots only)",TextSize=12}},
						{"TextLabel","987_6",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Update to character animations",TextSize=12}},
						{"TextLabel","987_7",47,{Position=u(0,0,0,0),Size=u(1,0,0,35),Text="   -   You can jump if you unpause after you walk off a part while humanoid state is \"running\"",TextSize=12}},
						{"TextLabel","987_8",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Renamed \"Spectate\" mode to \"Idle\"",TextSize=12}},
						{"TextLabel","986",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 10/11/25 - 2.31",TextSize=16}},
						{"TextLabel","986_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Emotes 😛",TextSize=12}},
						{"TextLabel","986_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Animation fixes (PLEASE dont be bad)",TextSize=12}},
						{"TextLabel","986_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed coyote frame abuse",TextSize=12}},
						{"TextLabel","985",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 07/03/26 - 2.33",TextSize=16}},
						{"TextLabel","985_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed camera zoom, NohBoard mouse, and client objects",TextSize=12}},
						{"TextLabel","984",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 10/10/26 - 2.33.1",TextSize=16}},
						{"TextLabel","984_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Mobile DynamicThumbstick middle tracking position & size",TextSize=12}},
						{"TextLabel","984_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Fixed first-person camera lock during pause and unpause",TextSize=12}},
						{"TextLabel","984_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Sub-pixel cursor UV normalization for cross-resolution aiming",TextSize=12}},
						{"TextLabel","983",35,{Position=u(0,0,0,0),Size=u(1,0,0,30),Text=" 10/12/26 - 2.34 (Master Engine Update)",TextSize=16}},
						{"TextLabel","983_1",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Official Roblox MicroProfiler replica (Ctrl+F6) with live TAS sync, Aggregate modes & scrubbing",TextSize=12}},
						{"TextLabel","983_2",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Custom mechanical keyboard & click sound engine with dynamic pitch modulation",TextSize=12}},
						{"TextLabel","983_3",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Client Object sync overhaul with EToH Kit v6.1.3 & 25-stud frustum culling",TextSize=12}},
						{"TextLabel","983_4",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Button Timer & Obby Mechanism Sync (countdown doors & pressure plates)",TextSize=12}},
						{"TextLabel","983_5",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Humanoid Death & Respawn recording across character respawns",TextSize=12}},
						{"TextLabel","983_6",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Tool equip, unequip, activate, and deactivate recording & playback",TextSize=12}},
						{"TextLabel","983_7",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Modern executor sandboxing (cloneref, gethui, syn.protect_gui, native LZ4)",TextSize=12}},
						{"TextLabel","983_8",35,{Position=u(0,0,0,0),Size=u(1,0,0,20),Text="   -   Settings UI alignment fix and Help page documentation overhaul",TextSize=12}}
					}},
					{"TextButton","ToggleMicroProfiler",20,{Position=u(0.25,0,0.5,0),Size=u(1,0,0,30),AnchorPoint=v2(0.5,0.5),Text="Toggle MicroProfiler",TextSize=16},{
						{"UICorner","UICorner",21,{}},
						{"UIStroke","UIStroke",48,{}}
					}},
					{"TextButton","1Model",20,{Position=u(0.25,0,0.5,0),Size=u(1,0,0,30),AnchorPoint=v2(0.5,0.5),Text="Unload HappaTAS",TextSize=16},{
						{"UICorner","UICorner",21,{}},
						{"UIStroke","UIStroke",48,{}}
					}}
				}}
			}},
			{"ScrollingFrame","HelpFrame",29,{Position=u(0,0,0,71),Size=u(0,400,1,-71),Visible=false,CanvasSize=u(0,0,4,0)},{
				{"Frame","List",19,{Position=u(0,20,0,10),Size=u(0,360,1,-60)},{
					{"UIListLayout","UIListLayout",44,{}},
					{"TextLabel","00",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="What is HappaTAS?",TextSize=16}},
					{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,83),AnchorPoint=v2(0.5,0),Text="      HappaTAS is the most powerful public tool on Roblox used to make Tool Assisted Speedruns (TAS). This is the executor port: one client-side script that saves to your executor's workspace folder. The original 1.0 version was called Happy_Liam's TAS Maker.",TextSize=14}},
					{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      A Tool Assisted Speedrun or Tool Assisted Superplay (TAS for short) is a run of an obby that's already been created, and is not being played in real time.",TextSize=14}},
					{"TextLabel","03",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,75),AnchorPoint=v2(0.5,0),Text="      The controls in this tool will allow you to create a TAS, and replay it ingame. Start at the top of the list of controls and make your way down to figure out how it works! If you don't like the preset controls, you can change their keybind in the Controls menu.",TextSize=14}},
					{"TextLabel","04",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Basic Controls",TextSize=16}},
					{"TextButton","05",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Idle",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,84),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,64),AnchorPoint=v2(0.5,0),Text="      Idle is the default mode. Switching to Idle exits everything TAS related so you can play the obby like normal.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","06",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Create",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,100),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1.03,0,0,34),AnchorPoint=v2(0.5,0),Text="      The create control switches you to create mode and pauses you, so you can start recording your TAS.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      Once you are in create mode, the controls below will give you further instructions on how to record gameplay.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","07",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Unpause",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,133),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      The unpause control can be pressed while in create mode and paused.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      Once you unpause, the TAS will begin recording. Any movement you do will show up in your recorded TAS unless you go back and remove it.",TextSize=14}},
								{"TextLabel","03",53,{Position=u(0.5,0,0,0),Size=u(1,0,0,33),AnchorPoint=v2(0.5,0),Text="      Exception: If you unpause the frame you jump off a ladder, you will be unpaused a frame earlier.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","08",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Pause",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,100),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      The unpause control can be pressed while in create mode and unpaused.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      Once you unpause, the TAS will stop recording. When paused, you can use other controls to remove parts of the TAS you don't want.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","09",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Back/Forward",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,140),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      The back and forward keys can be pressed while in create mode, they will pause you if you are unpaused.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,78),AnchorPoint=v2(0.5,0),Text="      While paused, holding these keys will move you back and forward in time. You can use them to back if you mess up a jump, or want to be faster. Once you unpause, you will resume from where you moved back to.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","10",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Test",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,70),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,50),AnchorPoint=v2(0.5,0),Text="      Using the Test control will play the TAS that you created. Just sit back, relax, and feel free to flex on your friends as you watch your character go.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","11",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Optimize TAS",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,95),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,78),AnchorPoint=v2(0.5,0),Text="      Want to improve the speed of your TAS? Use the optimize control while in idle mode and the still frames will be removed. (Removes frames where the camera is positioned the same as the previous frame, and there are no new animations playing.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","12",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Delete TAS",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,38),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,20),AnchorPoint=v2(0.5,0),Text="      RIP all your hard work :(",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextLabel","13",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Advanced Controls",TextSize=16}},
					{"TextButton","14",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Back/Forward 1 Frame",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,66),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      The Back 1 Frame and Forward 1 Frame controls are the same as the Back and Forward controls, but holding them down has no effect.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","15",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Return",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,100),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      The Return control can be used while in create mode, pressing it while unpaused will automatically pause you.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      This will bring you back to the most recent frame that you unpaused at.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","16",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Unpause 1 Frame",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,165),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,33),AnchorPoint=v2(0.5,0),Text="      The Unpause 1 Frame control can be used while paused in create mode.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      It is reccomend that you have Camera Lock (Paused) off if you are trying to control the camera while using this.",TextSize=14}},
								{"TextLabel","03",53,{Position=u(0.5,0,0,0),Size=u(1,0,0,64),AnchorPoint=v2(0.5,0),Text="      Exceptions: If you unpause the frame you jump off a ladder, you will be unpaused a frame earlier and for 2 frames. If you just landed a jump, you will be unpaused for 2 frames.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","17",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Look Around",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,142),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      The look around control can be used while paused in create mode, with the setting Camera Lock (Paused) on.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,76),AnchorPoint=v2(0.5,0),Text="      This will allow you to unlock the camera and look, around, pressing the key again will re-lock the camera. The camera will automatically go back to it's intended position if you unpause while looking around.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextLabel","18",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Settings",TextSize=16}},
					{"TextButton","20",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Lock Camera (Mode)",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,54),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      Changes whether the camera can be controlled or not in the specified mode.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","23",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Show Stats (Mode)",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,54),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      Changes whether or not the stats menu is open in the specified mode.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","22",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Restart When Testing",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,68),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Changes whether or not you go back to frame 1 when testing, useful to have off when you want to start from a certain frame while in create.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","24",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Stats Text Size",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,40),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,20),AnchorPoint=v2(0.5,0),Text="      Sets the size and text size of the stats menu.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextLabel","30",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Have fun :)",TextSize=16}},
					{"Frame","Spacer",19,{Position=u(0,0,0,0),Size=u(0,0,0,100)}},
					{"TextButton","21",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Playback Speed",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,80),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Changes the speed that the TAS will be replayed in test mode. Testing stats will always show when playback speed is not 1.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,34),AnchorPoint=v2(0.5,0),Text="      Negative/Backwards breaks animations but you can still try it out",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","19",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Interpolate Playback",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,200),Visible=false},{
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,30),AnchorPoint=v2(0.5,0),Text="      When Interpolate Playback is off, test mode will run the TAS by playing it one frame at a time.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,75),AnchorPoint=v2(0.5,0),Text="      When Interpolate Playback is on, a timer will begin when the playback starts. The position and properties of the character are set to be inbetween the two frames that were recorded at the time of playback (this was default starting in 2.23)",TextSize=14}},
								{"TextLabel","03",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,75),AnchorPoint=v2(0.5,0),Text="      It is recommended that you always keep interpolate on, because it is more stable under varying framerates. If you keep the same framerate throughout the recording and don't lag, turning this off might make the run look more smooth or realistic.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextLabel","25",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Saving and Loading",TextSize=16}},
					{"TextLabel","26",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,112),AnchorPoint=v2(0.5,0),Text="      In the save menu, add slots to save your TAS. Every slot is a compact .tas file inside HappaTasPort/<PlaceId>/ in your executor workspace, so slots only show up in the place they were saved in. Type in the name box to rename a slot (the file is renamed). There is no size or slot limit.",TextSize=14}},
					{"TextLabel","27",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Merging a TAS",TextSize=16}},
					{"TextLabel","28",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,114),AnchorPoint=v2(0.5,0),Text="      You are able to merge your TAS with one of your other saved TASes. By pressing the merge button, the TAS you load in from a save slot will load either before or after your current TAS. You will then be prompted to record a segment that stretches from the end of the first TAS to the beginning of the second TAS. The transition segment must end on the ground.",TextSize=14}},
					{"TextLabel","29",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Keyboard and Mouse Inputs",TextSize=16}},
					{"TextLabel","29a",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,147),AnchorPoint=v2(0.5,0),Text="      Your keys, right click, mouse wheel and mouse position are recorded together with every frame and replayed while testing, using the executor's input functions (keypress, mouse2press, mousemoveabs, mousescroll). The keys you use for the TAS menu are never recorded. Typing in a text box or clicking this menu is ignored. Keep the Roblox window focused during playback and keep your hands off the keyboard and mouse. The three Replay switches in Settings turn each part off.",TextSize=14}},
					{"TextLabel","29b",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Client Objects",TextSize=16}},
					{"TextLabel","29c",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,184),AnchorPoint=v2(0.5,0),Text="      Turn on 'Sync Client Objects' in Settings (off by default) to record the objects only your game client shows: moving, falling and swinging platforms, balloons, pushboxes, turret bullets, vanishers, beat blocks and other parts that move or change while you play (EToH kit objects). They are saved with the TAS and put back while testing and scrubbing. 'Smooth Client Objects' blends between recorded keyframes so they move smoothly at any FPS. Sounds, particles, lighting and GUIs are not synced.",TextSize=14}},
                    {"TextLabel","PortSettingsHeader",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Executor Port Settings",TextSize=16}},
                    {"TextLabel","PortSettingsDescription",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,195),AnchorPoint=v2(0.5,0),Text="      Show Completion Message controls the end-of-playback notice. Ignore Game Processed lets HappaTAS controls respond when Roblox marks an input as processed. NohBoard Cursor draws a fake cursor that stays still while the camera is locked (right click, shift lock, first person) and moves the hidden real cursor like the camera while testing. Invisible Mouse Speed scales that movement.",TextSize=14}},
					{"TextLabel","FeaturesHeader",30,{Position=u(0.5,0,0,0),Size=u(1,0,0,40),AnchorPoint=v2(0.5,0),Text="Feature Modules & Tools",TextSize=16}},
					{"TextButton","31",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="MicroProfiler",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,210),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      A copy of Roblox's MicroProfiler (F6). Time = last frame, Avg = average of the frames on the bar, Max = biggest frame (stays until a bigger one).",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Aggregate Infinite counts frames; picking it resets Max. Custom > TAS Timeline shows your TAS (green = current frame, click to jump there).",TextSize=14}},
								{"TextLabel","03",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,44),AnchorPoint=v2(0.5,0),Text="      Mode: Detailed, Timers, Counters, Frame, Hidden. [Dump] saves frames to HappaTasPort. Pause or Ctrl+P freezes it.",TextSize=14}},
								{"TextLabel","04",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Hover a menu to open it, click a line to pick it. If the text sits too high or low, change Settings > MicroProfiler Text Offset (- = up).",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","32",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Keyboard & Click Sounds",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,140),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Custom mechanical keyboard and mouse click sound feedback. Configure volume, enable keyboard sounds, and enable click sounds in Settings.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Sound Trigger Mode lets you select when audio plays: 0 for live recording, 1 for playback replay, or 2 for both. Dynamic Pitch Variation modulates sound pitch based on typing pace and key hold time.",TextSize=14}},
								{"TextLabel","03",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,24),AnchorPoint=v2(0.5,0),Text="      Sounds automatically suppress when typing in textboxes or navigating menus.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","33",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Mouse UV Normalization",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,110),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Normalizes cursor positions to camera viewport UV coordinates (0 to 1) after subtracting GuiService topbar insets.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,42),AnchorPoint=v2(0.5,0),Text="      Provides 1:1 cross-resolution aiming: replays on different screen resolutions or window sizes aim and click at the exact sub-pixel world location.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","34",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Death & Respawn Recording",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,110),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Record speedruns that use character deaths (killbricks, reset tricks, or respawn shortcuts) without crashing or resetting to Idle.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,42),AnchorPoint=v2(0.5,0),Text="      Terminal death frames are saved, and playback bridges smoothly across respawns, refreshing character and animation references on CharacterAdded.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","35",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Tool Actions Support",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,95),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Records and replays Tool equips, unequips, activations (clicks), and deactivations from your Character and Backpack.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,27),AnchorPoint=v2(0.5,0),Text="      Missing tools during playback are bypassed gracefully with a temporary status notice.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","36",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Button & Obby Mechanism Sync",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,135),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Direct integration with EToH Kit v6.1.3 button and timer mechanisms: timed switches, pressure plates, countdown doors, and disappearing segments.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,67),AnchorPoint=v2(0.5,0),Text="      Every press and release is saved with its frame. While paused the kit timer is frozen, scrubbing restores the button exactly, and testing runs the timer on the TAS clock.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}},
					{"TextButton","37",50,{Position=u(0,0,0,0),Size=u(1,0,0,40),Text="",TextSize=8},{
						{"UICorner","UICorner",5,{}},
						{"TextLabel","N",47,{Position=u(0,15,0,0),Size=u(0.7,0,1,0),Text="Frustum Culling & Sandboxing",TextSize=20}},
						{"TextLabel","Expand",51,{Position=u(1,-10,0.5,0),Size=u(0,30,0,30),AnchorPoint=v2(1,0.5),ZIndex=2,Text="+",TextSize=30},{
							{"UICorner","UICorner",5,{}}
						}},
						{"Frame","Expansion",52,{Position=u(0,0,1,-8),Size=u(1,0,0,135),Visible=false},{
							{"UICorner","UICorner",5,{}},
							{"Frame","InnerBox",19,{Position=u(0,10,0,15),Size=u(1,-20,1,-20)},{
								{"TextLabel","01",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,48),AnchorPoint=v2(0.5,0),Text="      Frustum culling filters out invisible and off-screen client objects unless within a 25-stud interaction radius, drastically reducing file size and recording lag.",TextSize=14}},
								{"UIListLayout","UIListLayout",32,{}},
								{"TextLabel","02",49,{Position=u(0.5,0,0,0),Size=u(1,0,0,67),AnchorPoint=v2(0.5,0),Text="      Metatable sandboxing with cloneref prevents game scripts from intercepting TAS operations. UI isolation mounts via gethui/syn.protect_gui, and native LZ4 provides instant file compression.",TextSize=14}}
							}}
						}},
						{"UIStroke","UIStroke",22,{}}
					}}
				}}
			}},
			{"UIStroke","UIStroke",17,{}}
		}}
}
local UI_TEMPLATES = {
	Control = {"Frame","ControlTemp",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
		{"TextLabel","N",30,{Position=u(0,0,0,0),Size=u(0.5,0,1,0),Text="Control",TextSize=16}},
		{"TextButton","Key",54,{Position=u(0.75,0,0.5,0),Size=u(0.4,0,0.7,0),AnchorPoint=v2(0.5,0.5),Text="Press Any Key",TextSize=16},{
			{"UICorner","UICorner",21,{}},
			{"UIStroke","UIStroke",22,{}}
		}},
		{"Frame","Border",39,{Position=u(0,0,1,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}}
	}},
	Slot = {"Frame","SlotTemp",34,{Position=u(0,0,0,0),Size=u(1,0,0,30)},{
		{"Frame","Buttons",55,{Position=u(0.75,0,0,15),Size=u(0.45,0,0,21),AnchorPoint=v2(0.5,0.5)},{
			{"UICorner","UICorner",5,{}},
			{"TextButton","Save",56,{Position=u(0,0,0,0),Size=u(0.4,0,1,0),Text="Save",TextSize=16}},
			{"TextButton","Load",56,{Position=u(0.4,0,0,0),Size=u(0.4,0,1,0),Text="Load",TextSize=16}},
			{"Frame","Line",57,{Position=u(0.4,0,0,0),Size=u(0,1,1,0),AnchorPoint=v2(0.5,0)}},
			{"Frame","Line",57,{Position=u(0.8,0,0,0),Size=u(0,1,1,0),AnchorPoint=v2(0.5,0)}},
			{"UIStroke","UIStroke",22,{}},
			{"ImageButton","Close",58,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,20),AnchorPoint=v2(0.5,0.5),Visible=false,LayoutOrder=28,ZIndex=2,Image="rbxassetid://3926307971",ImageRectOffset=v2(164,524),ImageRectSize=v2(36,36)}},
			{"ImageButton","Expand",58,{Position=u(0.9,0,0.5,0),Size=u(0,30,0,20),AnchorPoint=v2(0.5,0.5),LayoutOrder=24,ZIndex=2,Image="rbxassetid://3926307971",ImageRectOffset=v2(204,484),ImageRectSize=v2(36,36)}}
		}},
		{"TextLabel","IDtext",59,{Position=u(0,5,0,27),Size=u(0.15,0,0,30),Text="ID: 0",TextSize=12}},
		{"Frame","Border",39,{Position=u(0,0,0,0),Size=u(1,0,0,1),AnchorPoint=v2(0,1)}},
		{"TextBox","N",60,{Position=u(0.25,0,0,15),Size=u(0.48,0,0,21),AnchorPoint=v2(0.5,0.5),Text="",TextSize=13,PlaceholderText="Unnamed TAS"},{
			{"UICorner","UICorner",5,{}},
			{"UIStroke","UIStroke",41,{}}
		}},
		{"Frame","MoreButtons",55,{Position=u(0.75,0,0,42),Size=u(0.45,0,0,21),AnchorPoint=v2(0.5,0.5)},{
			{"UICorner","UICorner",5,{}},
			{"TextButton","Merge",56,{Position=u(0,0,0,0),Size=u(0.5,0,1,0),Text="Merge",TextSize=16}},
			{"TextButton","Delete",56,{Position=u(0.5,0,0,0),Size=u(0.5,0,1,0),Text="Delete",TextSize=16}},
			{"Frame","Line",57,{Position=u(0.5,0,0,0),Size=u(0,1,1,0),AnchorPoint=v2(0.5,0)}},
			{"UIStroke","UIStroke",22,{}}
		}}
	}},
	Z = {"Frame","Z",19,{Position=u(0,0,0,0),Size=u(0,1,0,1)}}
}

local UI = {}
do
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
	local enumCache = {}

	local function setProp(inst, k, v)
		local enumName = ENUM_FOR[k]
		if enumName and type(v) == "number" then
			local key = enumName .. ":" .. v
			local item = enumCache[key]
			if item == nil then
				local okE, it = pcall(function() return Enum[enumName]:FromValue(v) end)
				item = (okE and it) or false
				enumCache[key] = item
			end
			if not item then return end
			v = item
		end
		pcall(function() inst[k] = v end)
	end

	local function applyProps(inst, cls, props)
		if cls == "UICorner" then
			local tl = props.TopLeftRadius
			if tl and tl == props.TopRightRadius and tl == props.BottomLeftRadius and tl == props.BottomRightRadius then
				pcall(function() inst.CornerRadius = tl end)
				return
			end
		end
		for k, v in pairs(props) do setProp(inst, k, v) end
	end

	local function build(node)
		local cls, name, sid, props, kids = node[1], node[2], node[3], node[4], node[5]
		local inst = Instance.new(cls)
		inst.Name = name
		local style = UI_STYLES[sid]
		if style then applyProps(inst, cls, style[2]) end
		if props then applyProps(inst, cls, props) end
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

	function UI.Create()
		local gui = Instance.new("ScreenGui")
		gui.Name = "TASUserInterface"
		gui.ResetOnSpawn = false
		pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Global end)
		pcall(function() gui.DisplayOrder = 0 end)
		for _, node in ipairs(UI_TREE) do
			build(node).Parent = gui
		end
		UI.BuildSettingsRows(gui.MainMenu.SettingsFrame.List)
		return gui
	end

	-- parents a ScreenGui where game scripts can't read it (gethui -> CoreGui -> PlayerGui)
	function UI.Attach(gui)
		if Env.protectgui then pcall(Env.protectgui, gui) end
		local candidates = {}
		if Env.gethui then
			local ok, h = pcall(Env.gethui)
			if ok and typeof(h) == "Instance" then candidates[#candidates + 1] = h end
		end
		local core = svc("CoreGui")
		if core then candidates[#candidates + 1] = core end
		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
		if pg then candidates[#candidates + 1] = pg end

		for i, parent in ipairs(candidates) do
			if parent == pg then
				-- last resort: visible to game scripts, so don't use an obvious name
				gui.Name = HttpService and HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 12) or gui.Name
			end
			local ok = pcall(function() gui.Parent = parent end)
			if ok and gui.Parent ~= nil then
				UI.ParentName = (parent == pg) and "PlayerGui" or ((i == 1 and Env.gethui) and "gethui" or "CoreGui")
				return true
			end
		end
		return false
	end

	-- extra ScreenGuis (cursor, profiler) that sit above everything
	function UI.Overlay(name, displayOrder)
		local sg = Instance.new("ScreenGui")
		sg.Name = name
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
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

