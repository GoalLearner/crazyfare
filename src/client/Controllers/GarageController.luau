--!strict
-- The garage: vehicles (owned, selected, or priced in Gems), permanent upgrades, paint. Opens from a button that
-- shows whenever a round is not in progress. Every change goes through GarageAction; the server answers with
-- a ProfileSync, which redraws the panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local GarageController = {}

local openButton: TextButton
local panel: Frame
local gemsLabel: TextLabel
local vehicleList: Frame
local upgradeList: Frame
local paintRow: Frame
local isOpen = false
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
	local bar = UI.Bar({ Position = UDim2.fromOffset(60, y + 3), Size = UDim2.fromOffset(90, 8) }, UI.Accent, parent)
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
		local owned = stats.GemPrice <= 0 or profile.owned[id] == true
		local selected = profile.selected == id
		local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 72), LayoutOrder = i, BackgroundTransparency = if selected then 0.1 else 0.45, BackgroundColor3 = if selected then Color3.fromRGB(30, 50, 40) else UI.Panel }, vehicleList)
		UI.Corner(10, row)
		local swatch = UI.Frame({ Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(14, 52), BackgroundColor3 = stats.Color, BackgroundTransparency = 0 }, row)
		UI.Corner(4, swatch)
		UI.Label({ Position = UDim2.fromOffset(36, 8), Size = UDim2.fromOffset(220, 22), Text = string.upper(stats.DisplayName), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if owned then UI.White else UI.Muted }, row)
		UI.Label({ Position = UDim2.fromOffset(36, 34), Size = UDim2.fromOffset(250, 30), Text = stats.Description, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, TextScaled = false, TextSize = 13, TextWrapped = true }, row)
		local stat = UI.Frame({ Position = UDim2.fromOffset(296, 10), Size = UDim2.fromOffset(160, 56), BackgroundTransparency = 1 }, row)
		statBar(stat, 0, "SPEED", stats.TopSpeed / 100)
		statBar(stat, 18, "ACCEL", stats.Accel / 70)
		statBar(stat, 36, "GRIP", stats.Handling / 9)
		local label = if selected then "SELECTED" elseif owned then "SELECT" else string.format("%d GEMS", stats.GemPrice)
		local affordable = owned or profile.gems >= stats.GemPrice
		local b = button(label, if owned then Color3.fromRGB(60, 140, 80) else Color3.fromRGB(70, 110, 190), UDim2.fromOffset(104, 30), row, affordable and not selected)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -12, 0.5, 0)
		if not selected and affordable then
			b.Activated:Connect(function()
				action:FireServer(if owned then "Select" else "Buy", id)
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
		UI.Label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(110, 20), Text = string.upper(name), TextXAlignment = Enum.TextXAlignment.Left }, row)
		UI.Label({ Position = UDim2.fromOffset(12, 26), Size = UDim2.fromOffset(160, 14), Text = string.format("+%d%% per level", math.round(def.Per * 100)), TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 12 }, row)
		for pip = 1, def.Max do
			UI.Frame({ Position = UDim2.fromOffset(120 + (pip - 1) * 14, 10), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = if pip <= level then UI.Accent else Color3.fromRGB(50, 50, 58), BackgroundTransparency = 0 }, row)
		end
		local maxed = level >= def.Max
		local cost = if maxed then 0 else def.Costs[level + 1]
		local b = button(if maxed then "MAX" else string.format("%d GEMS", cost), Color3.fromRGB(70, 110, 190), UDim2.fromOffset(96, 30), row, not maxed and profile.gems >= cost)
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
	for i, entry in Config.Paint.Colors do
		local current = profile.paint == entry.Name
		local b = UI.New("TextButton", {
			Size = UDim2.fromOffset(34, 34),
			LayoutOrder = i,
			BackgroundColor3 = entry.Color,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = affordable and not current,
		}, paintRow) :: TextButton
		UI.Corner(17, b)
		UI.Stroke(if current then UI.White else Color3.fromRGB(40, 40, 48), if current then 3 else 1, b)
		if not current and affordable then
			b.Activated:Connect(function()
				action:FireServer("Paint", entry.Name)
			end)
		end
	end
	local reset = UI.New("TextButton", {
		Size = UDim2.fromOffset(60, 34),
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

local function render()
	local profile = State.profile
	if not profile then
		return
	end
	gemsLabel.Text = string.format("%d GEMS", profile.gems)
	renderVehicles(profile)
	renderUpgrades(profile)
	renderPaint(profile)
end

local function setOpen(open: boolean)
	isOpen = open
	panel.Visible = open
	if open then
		render()
	end
end

local function build()
	local screen = UI.Screen("CrazyFareGarage", 18) -- above the Pit Stop panel (15) so it reads while open
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

	panel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(820, 560), BackgroundTransparency = 0.05, Visible = false }, screen)
	UI.Corner(16, panel)
	UI.Label({ Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(200, 36), Text = "GARAGE", TextXAlignment = Enum.TextXAlignment.Left }, panel)
	gemsLabel = UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 18), Size = UDim2.fromOffset(200, 28), Text = "", TextColor3 = UI.Accent, TextXAlignment = Enum.TextXAlignment.Right }, panel)
	local close = button("X", Color3.fromRGB(80, 50, 50), UDim2.fromOffset(34, 34), panel, true)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 16)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	vehicleList = UI.Frame({ Position = UDim2.fromOffset(24, 64), Size = UDim2.fromOffset(490, 480), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, vehicleList)

	local right = UI.Frame({ Position = UDim2.fromOffset(530, 64), Size = UDim2.fromOffset(266, 480), BackgroundTransparency = 1 }, panel)
	UI.Label({ Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(200, 22), Text = "UPGRADES", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium }, right)
	UI.Label({ Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 14), Text = "Permanent, every vehicle", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, TextScaled = false, TextSize = 12 }, right)
	upgradeList = UI.Frame({ Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 160), BackgroundTransparency = 1 }, right)
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, upgradeList)
	UI.Label({ Position = UDim2.fromOffset(0, 220), Size = UDim2.fromOffset(200, 22), Text = string.format("PAINT  ·  %d GEMS", Config.Paint.Price), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium }, right)
	paintRow = UI.Frame({ Position = UDim2.fromOffset(0, 248), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, right)
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, paintRow)
end

local function onRound(payload: Types.RoundStatePayload)
	local parked = payload.phase ~= "Playing" and payload.phase ~= "Countdown"
	openButton.Visible = parked
	if not parked and isOpen then
		setOpen(false)
	end
end

function GarageController.Init()
	action = Remotes.Get("GarageAction")
	build()
	State.ProfileChanged:Connect(function()
		if isOpen then
			render()
		end
	end)
	State.RoundChanged:Connect(onRound)
end

function GarageController.Start() end

return GarageController
