--!strict
-- COLLECTION in the side stack (under INVITE), whenever you're not mid-round at the wheel: the cars you own, your best
-- license plate, your lifetime stats and your Weirdo cards (won in drops; missing ones dark), straight from your profile
-- (ProfileSync). Config.Collection, Config.Cosmetics.Cards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local CollectionController = {}

local openButton: TextButton
local panel: Frame
local carsLabel: TextLabel
local carList: Frame
local licenseLabel: TextLabel
local statList: Frame
local cardsLabel: TextLabel
local cardGrid: Frame
local isOpen = false

local CARD_TILE = Vector2.new(84, 56)

local function render()
	local profile = State.profile
	for _, list in { carList, statList, cardGrid } do
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	if not profile then
		return
	end
	local order = Config.Vehicles.Order
	local owned = 0
	for i, id in order do
		local stats = Config.Vehicles.Stats[id]
		local has = profile.owned[id] == true or (stats ~= nil and stats.GemPrice == 0 and not stats.RobuxOnly)
		if has then
			owned += 1
		end
		UI.Label({
			Size = UDim2.new(1, 0, 0, 22),
			Text = (if has then "\u{2714} " else "\u{25A1} ") .. string.upper(if stats then stats.DisplayName else id),
			TextColor3 = if has then UI.White else UI.Muted,
			Font = UI.FontMedium,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
		}, carList)
	end
	carsLabel.Text = string.format(Config.Collection.Cars, owned, #order)
	local grades = Config.License.Grades
	local best = profile.bestLicense
	licenseLabel.Text = if best > 0 then grades[best] else "-"
	licenseLabel.TextColor3 = if best > 0 then Config.License.Colors[best] else UI.Muted
	for i, stat in Config.Collection.Stats do
		local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = i }, statList)
		UI.Label({ Size = UDim2.fromScale(0.6, 1), Text = stat.Label, TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, row)
		UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.4, 1), Text = tostring(profile.stats[stat.Key] or 0), TextXAlignment = Enum.TextXAlignment.Right }, row)
	end
	-- Weirdo cards: yours lit in their costume colors, the rest dark
	local ownedCards = if profile.inventory then profile.inventory.Cards or {} else {}
	local cardCount = 0
	for i, id in Config.Cosmetics.CardOrder do
		local def = Config.Cosmetics.Cards[id]
		local has = (ownedCards[id] or 0) > 0
		if has then
			cardCount += 1
		end
		local tile = UI.Frame({ LayoutOrder = i, BackgroundColor3 = if has then def.Shirt:Lerp(Color3.new(0, 0, 0), 0.55) else Color3.fromRGB(32, 32, 38), BackgroundTransparency = 0 }, cardGrid)
		UI.Corner(8, tile)
		UI.Stroke(if has then Config.Drops.Colors[def.Rarity] else Color3.fromRGB(50, 50, 58), if has then 2 else 1, tile)
		UI.Label({ Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 26), Text = if has then def.Icon else "?", TextColor3 = if has then UI.White else UI.Muted }, tile)
		UI.Label({ Position = UDim2.new(0, 3, 1, -22), Size = UDim2.new(1, -6, 0, 18), Text = if has then def.Name else "", TextColor3 = UI.White, Font = UI.FontMedium }, tile)
	end
	cardsLabel.Text = string.format(Config.Collection.Cards, cardCount, #Config.Cosmetics.CardOrder)
end

local function setOpen(open: boolean)
	isOpen = open
	panel.Visible = open
	if open then
		render()
	end
end

-- Parked: between rounds, or not driving at all (on foot, in the depot).
local function onRound(payload: Types.RoundStatePayload)
	local parked = (payload.phase ~= "Playing" and payload.phase ~= "Countdown") or (State.sessionState ~= "Driver" and State.sessionState ~= "")
	openButton.Visible = parked
	if not parked and isOpen then
		setOpen(false)
	end
end

local function build()
	local screen = UI.Screen("CrazyFareCollection", 16)
	openButton = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24 + Config.Hud.MinimapSize + 10 + (34 + 8) * 5),
		Size = UDim2.fromOffset(Config.Hud.MinimapSize, 34),
		BackgroundColor3 = Color3.fromRGB(40, 120, 120),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = Config.Collection.Button,
		Visible = false,
	}, screen) :: TextButton
	UI.Corner(8, openButton)
	openButton.Activated:Connect(function()
		setOpen(not isOpen)
	end)

	panel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(820, 340), BackgroundTransparency = 0.05, Visible = false }, screen)
	UI.CenterBelowTopbar(panel)
	UI.Corner(16, panel)
	UI.Label({ Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(240, 36), Text = Config.Collection.Title, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	local close = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color3.fromRGB(80, 50, 50),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = "X",
	}, panel) :: TextButton
	UI.Corner(8, close)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	carsLabel = UI.Label({ Position = UDim2.fromOffset(24, 60), Size = UDim2.fromOffset(220, 20), Text = "", TextColor3 = UI.Accent, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	carList = UI.Frame({ Position = UDim2.fromOffset(24, 86), Size = UDim2.fromOffset(220, 230), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, carList)
	UI.Label({ Position = UDim2.fromOffset(276, 60), Size = UDim2.fromOffset(220, 20), Text = Config.Collection.BestLicense, TextColor3 = UI.Accent, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	licenseLabel = UI.Label({ Position = UDim2.fromOffset(276, 84), Size = UDim2.fromOffset(220, 40), Text = "-", TextXAlignment = Enum.TextXAlignment.Left }, panel)
	statList = UI.Frame({ Position = UDim2.fromOffset(276, 136), Size = UDim2.fromOffset(220, 180), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, statList)
	cardsLabel = UI.Label({ Position = UDim2.fromOffset(528, 60), Size = UDim2.fromOffset(264, 20), Text = "", TextColor3 = UI.Accent, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	cardGrid = UI.Frame({ Position = UDim2.fromOffset(528, 86), Size = UDim2.fromOffset(264, 242), BackgroundTransparency = 1 }, panel)
	UI.New("UIGridLayout", { CellSize = UDim2.fromOffset(CARD_TILE.X, CARD_TILE.Y), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, cardGrid)
end

function CollectionController.Init()
	build()
	State.RoundChanged:Connect(onRound)
	State.SessionChanged:Connect(function()
		local round = State.round
		if round then
			onRound(round)
		end
	end)
	State.ProfileChanged:Connect(function()
		if isOpen then
			render()
		end
	end)
end

function CollectionController.Start() end

return CollectionController
