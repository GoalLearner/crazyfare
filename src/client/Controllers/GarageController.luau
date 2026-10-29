--!strict
-- The garage: vehicles (owned, selected, or priced in Gems), permanent upgrades, paint. Opens from a button that
-- shows whenever a round is not in progress, and the Pit Stop panel hosts the same content behind its GARAGE tab
-- (Mount/Unmount move the content frame). Every change goes through GarageAction; the server answers with a
-- ProfileSync, which redraws the panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)
local PhantomOffer = require(script.Parent.Parent.PhantomOffer)
local SoundController = require(script.Parent.SoundController)

local GarageController = {}

local CONTENT_WIDTH = 820
local CONTENT_HEIGHT = 508 -- gems line + the 480-tall lists
local STANDALONE_CONTENT_Y = 56 -- below the title row of the garage's own panel

-- Size of the content frame, for a host panel (the Pit Stop) to size itself around.
GarageController.ContentSize = Vector2.new(CONTENT_WIDTH, CONTENT_HEIGHT)

local openButton: TextButton
local panel: Frame
local content: Frame
local gemsLabel: TextLabel
local vehicleList: ScrollingFrame
local upgradeList: Frame
local paintRow: Frame
local trailRow: Frame
local hornRow: Frame
local isOpen = false
local mounted = false
local parked = false
local action: RemoteEvent

local function button(text: string, color: Color3, size: UDim2, parent: Instance, enabled: boolean): TextButton
	local b = UI.New("TextButton", {
		Size = size,
		BackgroundColor3 = if enabled then color else Color3.fromRGB(50, 50, 58),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 15,
		TextColor3 = if enabled then UI.White else UI.Muted,
		Text = text,
		AutoButtonColor = enabled,
	}, parent) :: TextButton
	UI.Corner(8, b)
	return b
end

local function statBar(parent: Instance, y: number, label: string, fraction: number)
	UI.Label({ Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(56, 14), Text = label, TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, parent)
	local bar = UI.Bar({ Position = UDim2.fromOffset(56, y + 3), Size = UDim2.fromOffset(80, 8) }, UI.Accent, parent)
	UI.SetBar(bar, fraction)
end

local function renderVehicles(profile: Types.ProfilePayload)
	for _, child in vehicleList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, id in Config.Vehicles.Order do
		local stats = Config.Vehicles.Stats[id]
		if not stats then
			continue
		end
		local owned = (stats.GemPrice <= 0 and not stats.RobuxOnly) or profile.owned[id] == true
		local selected = profile.selected == id
		local row = UI.Frame({ Size = UDim2.new(1, -10, 0, 72), LayoutOrder = i, BackgroundTransparency = if selected then 0.1 else 0.45, BackgroundColor3 = if selected then Color3.fromRGB(30, 50, 40) else UI.Panel }, vehicleList)
		UI.Corner(10, row)
		local swatch = UI.Frame({ Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(14, 52), BackgroundColor3 = stats.Color, BackgroundTransparency = 0 }, row)
		UI.Corner(4, swatch)
		local mythic = stats.Mythic == true
		UI.Label({ Position = UDim2.fromOffset(36, 8), Size = UDim2.fromOffset(200, 22), Text = string.upper(stats.DisplayName), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if mythic then Config.Vehicles.Phantom.Glow elseif owned then UI.White else UI.Muted }, row)
		-- a Mythic car shows how rare it is (and your serial) instead of its blurb; the shop has the blurb
		local detail = stats.Description
		if mythic then
			local serial = profile.phantomSerial
			detail = PhantomOffer.OwnersText() .. "\n" .. (if owned and serial > 0 then string.format(Config.Vehicles.Phantom.YoursLine, serial) elseif owned then "" else PhantomOffer.StatusText())
		end
		UI.Label({ Position = UDim2.fromOffset(36, 34), Size = UDim2.fromOffset(200, 30), Text = detail, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, TextScaled = false, TextSize = 13, TextWrapped = true }, row)
		local stat = UI.Frame({ Position = UDim2.fromOffset(244, 10), Size = UDim2.fromOffset(140, 56), BackgroundTransparency = 1 }, row)
		statBar(stat, 0, "SPEED", stats.TopSpeed / 100)
		statBar(stat, 18, "ACCEL", stats.Accel / 70)
		statBar(stat, 36, "GRIP", stats.Handling / 9)
		local productId = Config.Monetization.VehicleProducts[id] or 0
		local robux = Config.Monetization.VehicleRobux[id] or 0
		-- Robux-only cars: the button buys with Robux (TEST in Studio while the id is 0)
		if stats.RobuxOnly and not owned then
			-- a Mythic car is for sale only inside its offer window
			local onSale = not mythic or PhantomOffer.SecondsLeft() > 0
			local canBuy = onSale and (productId > 0 or RunService:IsStudio())
			local text = if not onSale then Config.Vehicles.Phantom.DropOnlyButton elseif productId > 0 then string.format("R$ %d", robux) elseif canBuy then "TEST" else "SOON"
			local rb = button(text, Color3.fromRGB(60, 140, 80), UDim2.fromOffset(88, 30), row, canBuy)
			rb.AnchorPoint = Vector2.new(1, 0.5)
			rb.Position = UDim2.new(1, -12, 0.5, 0)
			if canBuy then
				rb.Activated:Connect(function()
					if productId > 0 then
						MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
					else
						Remotes.Get("Debug"):FireServer("Grant", id)
					end
				end)
			end
			continue
		end
		local label = if selected then "SELECTED" elseif owned then "SELECT" else string.format("%d GEMS", stats.GemPrice)
		local affordable = owned or profile.gems >= stats.GemPrice
		local b = button(label, if owned then Color3.fromRGB(60, 140, 80) else Color3.fromRGB(70, 110, 190), UDim2.fromOffset(88, 30), row, affordable and not selected)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -12, 0.5, 0)
		if not selected and affordable then
			b.Activated:Connect(function()
				action:FireServer(if owned then "Select" else "Buy", id)
			end)
		end
		if not owned and productId > 0 then
			local rb = button("R$", Color3.fromRGB(60, 140, 80), UDim2.fromOffset(44, 30), row, true)
			rb.AnchorPoint = Vector2.new(1, 0.5)
			rb.Position = UDim2.new(1, -104, 0.5, 0)
			rb.Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
			end)
		end
	end
end

local function renderUpgrades(profile: Types.ProfilePayload)
	for _, child in upgradeList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, name in Config.Upgrades.Order do
		local def = Config.Upgrades[name]
		local level = profile.upgrades[name] or 0
		local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 46), LayoutOrder = i, BackgroundTransparency = 0.45 }, upgradeList)
		UI.Corner(8, row)
		UI.Label({ Position = UDim2.fromOffset(12, 5), Size = UDim2.fromOffset(90, 20), Text = string.upper(name), TextXAlignment = Enum.TextXAlignment.Left }, row)
		UI.Label({ Position = UDim2.fromOffset(104, 8), Size = UDim2.fromOffset(70, 14), Text = string.format("+%s%%/LV", tostring(math.round(def.Per * 1000) / 10)), TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 12 }, row)
		for pip = 1, def.Max do
			UI.Frame({ Position = UDim2.fromOffset(12 + (pip - 1) * 15, 30), Size = UDim2.fromOffset(11, 10), BackgroundColor3 = if pip <= level then UI.Accent else Color3.fromRGB(50, 50, 58), BackgroundTransparency = 0 }, row)
		end
		local maxed = level >= def.Max
		local cost = if maxed then 0 else def.Costs[level + 1]
		local b = button(if maxed then "MAX" else string.format("%d GEMS", cost), Color3.fromRGB(70, 110, 190), UDim2.fromOffset(84, 30), row, not maxed and profile.gems >= cost)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -10, 0.5, 0)
		if not maxed and profile.gems >= cost then
			b.Activated:Connect(function()
				action:FireServer("Upgrade", name)
			end)
		end
	end
end

local function renderPaint(profile: Types.ProfilePayload)
	for _, child in paintRow:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local affordable = profile.gems >= Config.Paint.Price
	local ownedPaints = if profile.inventory then profile.inventory.Paints or {} else {}
	-- the next level paint you don't have yet shows locked with its level (Config.Levels)
	local teaserPaint, teaserLevel = "", 0
	for _, reward in Config.Levels.Rewards do
		if reward.Kind == "Paint" and (ownedPaints[reward.Ref or ""] or 0) <= 0 then
			teaserPaint, teaserLevel = reward.Ref or "", reward.Level
			break
		end
	end
	for i, entry in Config.Paint.Colors do
		-- paints won in drops apply free (a check mark); drop-only colors show only once you own them
		local owned = (ownedPaints[entry.Name] or 0) > 0
		if entry.DropOnly and not owned then
			if entry.Name == teaserPaint then
				local locked = UI.New("TextButton", {
					Size = UDim2.fromOffset(28, 28),
					LayoutOrder = i,
					BackgroundColor3 = entry.Color,
					BackgroundTransparency = 0.6,
					BorderSizePixel = 0,
					Font = UI.Font,
					TextSize = 9,
					TextColor3 = UI.White,
					TextStrokeTransparency = 0.3,
					Text = string.format(Config.Levels.LockedMark, teaserLevel),
					AutoButtonColor = false,
				}, paintRow) :: TextButton
				UI.Corner(14, locked)
			end
			continue
		end
		local current = profile.paint == entry.Name
		local usable = owned or affordable
		local b = UI.New("TextButton", {
			Size = UDim2.fromOffset(28, 28),
			LayoutOrder = i,
			BackgroundColor3 = entry.Color,
			BorderSizePixel = 0,
			Font = UI.Font,
			TextSize = 14,
			TextColor3 = UI.White,
			TextStrokeTransparency = 0.3,
			Text = if owned and not current then "\u{2713}" elseif entry.Material then Config.Paint.MaterialMark else "",
			AutoButtonColor = usable and not current,
		}, paintRow) :: TextButton
		UI.Corner(14, b)
		UI.Stroke(if current then UI.White else Color3.fromRGB(40, 40, 48), if current then 3 else 1, b).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		if not current and usable then
			b.Activated:Connect(function()
				action:FireServer("Paint", entry.Name)
			end)
		end
	end
	local reset = UI.New("TextButton", {
		Size = UDim2.fromOffset(52, 28),
		LayoutOrder = 99,
		BackgroundColor3 = Color3.fromRGB(50, 50, 58),
		BorderSizePixel = 0,
		Font = UI.FontMedium,
		TextSize = 12,
		TextColor3 = UI.Muted,
		Text = "NONE",
	}, paintRow) :: TextButton
	UI.Corner(8, reset)
	reset.Activated:Connect(function()
		action:FireServer("Paint", "")
	end)
end

-- TRAIL / HORN: the ones you won in drops, the equipped one outlined, NONE to take it off. A horn plays when you tap it.
local function renderCosmetics(row: Frame, slot: string, order: { string }, names: { [string]: string }, colors: { [string]: Color3 }, profile: Types.ProfilePayload)
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local owned = if profile.inventory then profile.inventory[slot .. "s"] or {} else {}
	local equipped = if profile.equipped then (if slot == "Trail" then profile.equipped.Trail else profile.equipped.Horn) else ""
	local any = false
	for i, id in order do
		if (owned[id] or 0) <= 0 then
			continue
		end
		any = true
		local current = equipped == id
		local b = button(names[id] or id, colors[id] or Color3.fromRGB(70, 110, 190), UDim2.fromOffset(84, 26), row, true)
		b.LayoutOrder = i
		b.TextSize = 11
		UI.Stroke(if current then UI.White else Color3.fromRGB(40, 40, 48), if current then 3 else 1, b).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		b.Activated:Connect(function()
			if slot == "Horn" then
				SoundController.PlayHorn(id)
			end
			if not current then
				action:FireServer(slot, id)
			end
		end)
	end
	if not any then
		UI.Label({ Size = UDim2.new(1, 0, 0, 26), Text = Config.Cosmetics.EmptyLine, TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 12 }, row)
		return
	end
	local none = button(Config.Cosmetics.NoneLabel, Color3.fromRGB(50, 50, 58), UDim2.fromOffset(52, 26), row, equipped ~= "")
	none.LayoutOrder = 99
	none.TextSize = 11
	if equipped ~= "" then
		none.Activated:Connect(function()
			action:FireServer(slot, "")
		end)
	end
end

local function renderTrailsAndHorns(profile: Types.ProfilePayload)
	local c = Config.Cosmetics
	local trailNames: { [string]: string } = {}
	local trailColors: { [string]: Color3 } = {}
	for id, def in c.Trails do
		trailNames[id] = def.Name
		trailColors[id] = def.Colors[1]:Lerp(Color3.new(0, 0, 0), 0.35)
	end
	local hornNames: { [string]: string } = {}
	local hornColors: { [string]: Color3 } = {}
	for id, def in c.Horns do
		hornNames[id] = def.Name
		hornColors[id] = Config.Drops.Colors[def.Rarity]:Lerp(Color3.new(0, 0, 0), 0.45)
	end
	local trailOrder = table.clone(c.TrailOrder)
	for _, id in c.EarnedTrailOrder do
		table.insert(trailOrder, id) -- won by playing (the streak calendar, Config.Levels)
	end
	renderCosmetics(trailRow, "Trail", trailOrder, trailNames, trailColors, profile)
	renderCosmetics(hornRow, "Horn", c.HornOrder, hornNames, hornColors, profile)
end

local function render()
	local profile = State.profile
	if not profile then
		return
	end
	gemsLabel.Text = string.format("%d GEMS", profile.gems)
	renderVehicles(profile)
	renderUpgrades(profile)
	renderPaint(profile)
	renderTrailsAndHorns(profile)
end

local function setOpen(open: boolean)
	if open and mounted then
		return -- the Pit Stop is showing the garage already
	end
	isOpen = open
	panel.Visible = open
	if open then
		render()
	end
end

local function build()
	local screen = UI.Screen("CrazyFareGarage", 18) -- above the Pit Stop panel (15) so it reads while open
	screen:SetAttribute(Config.Title.KeepAttribute, true) -- the title screen's GARAGE opens it
	openButton = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24 + Config.Hud.MinimapSize + 10),
		Size = UDim2.fromOffset(Config.Hud.MinimapSize, 34),
		BackgroundColor3 = Color3.fromRGB(40, 44, 56),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = "GARAGE",
		Visible = false,
	}, screen) :: TextButton
	UI.Corner(8, openButton)
	openButton.Activated:Connect(function()
		setOpen(not isOpen)
	end)

	panel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(CONTENT_WIDTH, STANDALONE_CONTENT_Y + CONTENT_HEIGHT + 16), BackgroundTransparency = 0.05, Visible = false }, screen)
	UI.CenterBelowTopbar(panel)
	UI.Corner(16, panel)
	UI.Label({ Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(200, 36), Text = "GARAGE", TextXAlignment = Enum.TextXAlignment.Left }, panel)
	local close = button("X", Color3.fromRGB(80, 50, 50), UDim2.fromOffset(34, 34), panel, true)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 16)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	-- Everything below the title lives in one frame so the Pit Stop can host it behind its GARAGE tab.
	content = UI.Frame({ Position = UDim2.fromOffset(0, STANDALONE_CONTENT_Y), Size = UDim2.fromOffset(CONTENT_WIDTH, CONTENT_HEIGHT), BackgroundTransparency = 1 }, panel)
	gemsLabel = UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 0), Size = UDim2.fromOffset(200, 24), Text = "", TextColor3 = UI.Accent, TextXAlignment = Enum.TextXAlignment.Right }, content)

	vehicleList = UI.New("ScrollingFrame", {
		Position = UDim2.fromOffset(24, 28),
		Size = UDim2.fromOffset(500, 480),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, content) :: ScrollingFrame
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, vehicleList)

	local right = UI.Frame({ Position = UDim2.fromOffset(530, 28), Size = UDim2.fromOffset(266, 480), BackgroundTransparency = 1 }, content)
	UI.Label({ Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(200, 22), Text = "UPGRADES", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium }, right)
	UI.Label({ Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 14), Text = "Permanent, every vehicle", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, TextScaled = false, TextSize = 12 }, right)
	upgradeList = UI.Frame({ Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 160), BackgroundTransparency = 1 }, right)
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, upgradeList)
	UI.Label({ Position = UDim2.fromOffset(0, 220), Size = UDim2.fromOffset(200, 22), Text = string.format("PAINT  ·  %d GEMS", Config.Paint.Price), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium }, right)
	paintRow = UI.Frame({ Position = UDim2.fromOffset(0, 248), Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1 }, right)
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, paintRow)
	UI.Label({ Position = UDim2.fromOffset(0, 318), Size = UDim2.fromOffset(200, 22), Text = Config.Cosmetics.TrailRow, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium }, right)
	trailRow = UI.Frame({ Position = UDim2.fromOffset(0, 344), Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1 }, right)
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, trailRow)
	UI.Label({ Position = UDim2.fromOffset(0, 400), Size = UDim2.fromOffset(200, 22), Text = Config.Cosmetics.HornRow, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium }, right)
	hornRow = UI.Frame({ Position = UDim2.fromOffset(0, 426), Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1 }, right)
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, hornRow)
end

-- The title screen's GARAGE button.
function GarageController.Open()
	setOpen(true)
end

function GarageController.Close()
	if isOpen then
		setOpen(false)
	end
end

function GarageController.IsOpen(): boolean
	return isOpen
end

-- Show the garage content inside another panel (the Pit Stop's GARAGE tab). The side button hides meanwhile.
function GarageController.Mount(parent: Instance, position: UDim2)
	if mounted then
		return
	end
	mounted = true
	if isOpen then
		setOpen(false)
	end
	content.Position = position
	content.Parent = parent
	openButton.Visible = false
	render()
end

-- Give the content back to the garage's own panel.
function GarageController.Unmount()
	if not mounted then
		return
	end
	mounted = false
	content.Position = UDim2.fromOffset(0, STANDALONE_CONTENT_Y)
	content.Parent = panel
	openButton.Visible = parked
end

-- Parked: between rounds, or not driving at all (on foot, in the depot).
local function onRound(payload: Types.RoundStatePayload)
	parked = (payload.phase ~= "Playing" and payload.phase ~= "Countdown") or (State.sessionState ~= "Driver" and State.sessionState ~= "")
	openButton.Visible = parked and not mounted and State.sessionState ~= "Title" -- the title screen has its own GARAGE
	if not parked and isOpen then
		setOpen(false)
	end
end

function GarageController.Init()
	action = Remotes.Get("GarageAction")
	build()
	State.SessionChanged:Connect(function()
		local round = State.round
		if round then
			onRound(round)
		end
	end)
	State.ProfileChanged:Connect(function()
		if isOpen or mounted then
			render()
		end
	end)
	PhantomOffer.OnOwnersChanged(function()
		if isOpen or mounted then
			render()
		end
	end)
	State.RoundChanged:Connect(onRound)
end

function GarageController.Start() end

return GarageController
