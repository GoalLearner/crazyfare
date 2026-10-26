--!strict
-- The Pit Stop panel between rounds: the cards the server offered, their prices, your cash, and a countdown.
-- Buying sends PitStopBuy; the server answers with a fresh offer that marks the card bought.
-- A GARAGE tab hosts the garage inside the same panel, so cars, upgrades and paint can change between rounds.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)
local GarageController = require(script.Parent.GarageController)

local PitStopController = {}

local panel: Frame
local cashLabel: TextLabel
local timerLabel: TextLabel
local footer: TextLabel
local cardRow: Frame
local reopenButton: TextButton
local tabButtons: { [string]: TextButton } = {}
local tab = "cards" -- "cards" | "garage"
local collapsed = false
local wasInPitStop = false
local buyRemote: RemoteEvent

local CARD_WIDTH = 118
local CARD_HEIGHT = 170
local HEADER_HEIGHT = 84 -- tab row, then the cash / countdown row
local TAB_WIDTH = 120
local TAB_HEIGHT = 34
local CARDS_WIDTH = math.max(Config.PitStop.CardsOffered * (CARD_WIDTH + 10) + 50, 420)
local CARDS_SIZE = UDim2.fromOffset(CARDS_WIDTH, CARD_HEIGHT + 130)
local GARAGE_SIZE = UDim2.fromOffset(GarageController.ContentSize.X, HEADER_HEIGHT + GarageController.ContentSize.Y + 16)

local function styleTab(button: TextButton, active: boolean)
	button.BackgroundColor3 = if active then Color3.fromRGB(44, 62, 84) else Color3.fromRGB(28, 30, 40)
	button.TextColor3 = if active then UI.White else UI.Muted
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if active then UI.Accent else Color3.fromRGB(50, 52, 64)
	end
end

-- Lays the panel out for the current tab: the cards, or the garage content mounted below the header.
local function applyTab()
	local garage = tab == "garage"
	for name, button in tabButtons do
		styleTab(button, name == tab)
	end
	cardRow.Visible = not garage
	cashLabel.Visible = not garage
	footer.Visible = not garage
	panel.Size = if garage then GARAGE_SIZE else CARDS_SIZE
	if garage then
		GarageController.Mount(panel, UDim2.fromOffset(0, HEADER_HEIGHT))
	else
		GarageController.Unmount()
	end
end

local function setTab(name: string)
	tab = name
	applyTab()
end

local function build()
	local screen = UI.Screen("CrazyFarePitStop", 15)
	panel = UI.Frame({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = CARDS_SIZE,
		BackgroundTransparency = 0.08,
		Visible = false,
	}, screen)
	UI.Corner(16, panel)
	for i, spec in { { id = "cards", label = "PIT STOP" }, { id = "garage", label = "GARAGE" } } do
		local button = UI.New("TextButton", {
			Position = UDim2.fromOffset(24 + (i - 1) * (TAB_WIDTH + 8), 14),
			Size = UDim2.fromOffset(TAB_WIDTH, TAB_HEIGHT),
			BorderSizePixel = 0,
			Font = UI.Font,
			TextSize = 16,
			Text = spec.label,
			AutoButtonColor = true,
		}, panel) :: TextButton
		UI.Corner(8, button)
		UI.Stroke(Color3.fromRGB(50, 52, 64), 2, button)
		tabButtons[spec.id] = button
		local id = spec.id
		button.Activated:Connect(function()
			setTab(id)
		end)
	end
	local close = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
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
		collapsed = true
		setTab("cards") -- gives the garage back to its own button while the panel is away
		panel.Visible = false
		reopenButton.Visible = true
	end)
	reopenButton = UI.New("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(160, 32),
		BackgroundColor3 = Color3.fromRGB(60, 140, 80),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 15,
		TextColor3 = UI.White,
		Text = "OPEN PIT STOP",
		Visible = false,
	}, screen) :: TextButton
	UI.Corner(8, reopenButton)
	reopenButton.Activated:Connect(function()
		collapsed = false
		reopenButton.Visible = false
		panel.Visible = true
	end)
	cashLabel = UI.Label({ Position = UDim2.fromOffset(24, 54), Size = UDim2.fromOffset(200, 24), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Cash, Text = "$0" }, panel)
	timerLabel = UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 54), Size = UDim2.fromOffset(200, 24), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "" }, panel)
	footer = UI.Label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -40, 0, 18), TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "Boosts last one round. Unspent cash counts toward the quota." }, panel)
	cardRow = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 88), Size = UDim2.new(1, -40, 0, CARD_HEIGHT), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, cardRow)
	applyTab()
end

local function renderCards(offer: Types.PitStopOfferPayload)
	for _, child in cardRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, card in offer.cards do
		local affordable = offer.cash >= card.price and offer.buysLeft > 0
		local frame = UI.Frame({ Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT), LayoutOrder = i, BackgroundTransparency = if card.bought then 0.45 else 0.15, BackgroundColor3 = Color3.fromRGB(28, 30, 40) }, cardRow)
		UI.Corner(12, frame)
		UI.Stroke(if card.bought then UI.Cash else Color3.fromRGB(70, 72, 84), 2, frame)
		UI.Label({ Position = UDim2.fromOffset(8, 10), Size = UDim2.new(1, -16, 0, 40), Text = string.upper(card.name), TextColor3 = UI.Warn }, frame)
		UI.Label({ Position = UDim2.fromOffset(8, 54), Size = UDim2.new(1, -16, 0, 56), Text = card.effect, TextColor3 = UI.White, Font = UI.FontMedium, TextWrapped = true, TextScaled = false, TextSize = 14 }, frame)
		local button = UI.New("TextButton", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -16, 0, 34),
			BackgroundColor3 = if card.bought then Color3.fromRGB(40, 70, 48) else (if affordable then Color3.fromRGB(60, 140, 80) else Color3.fromRGB(50, 50, 58)),
			BorderSizePixel = 0,
			Font = UI.Font,
			TextSize = 16,
			TextColor3 = if affordable or card.bought then UI.White else UI.Muted,
			Text = if card.bought then "BOUGHT" else UI.Money(card.price),
			AutoButtonColor = affordable and not card.bought,
		}, frame) :: TextButton
		UI.Corner(8, button)
		if not card.bought and affordable then
			local id = card.id
			button.Activated:Connect(function()
				buyRemote:FireServer(id)
			end)
		end
	end
end

local function refresh()
	local offer = State.pitStop
	local inPitStop = offer ~= nil and State.GetPhase() == "PitStop"
	if offer and inPitStop then
		if not wasInPitStop then
			collapsed = false
			tab = "cards" -- every Pit Stop opens on the cards
		end
		cashLabel.Text = string.format("%s  ·  %d pick%s left", UI.Money(offer.cash), offer.buysLeft, if offer.buysLeft == 1 then "" else "s")
		renderCards(offer)
		applyTab()
		panel.Visible = not collapsed
		reopenButton.Visible = collapsed
	else
		panel.Visible = false
		reopenButton.Visible = false
		collapsed = false
		if tab ~= "cards" then
			setTab("cards")
		end
	end
	wasInPitStop = inPitStop
end

function PitStopController.Init()
	buyRemote = Remotes.Get("PitStopBuy")
	build()
	State.PitStopChanged:Connect(refresh)
	State.RoundChanged:Connect(refresh)
end

function PitStopController.Start()
	RunService.RenderStepped:Connect(function()
		if not panel.Visible then
			return
		end
		local offer = State.pitStop
		if offer then
			timerLabel.Text = "Round starts in " .. math.max(0, math.ceil(offer.endsAt - workspace:GetServerTimeNow()))
		end
	end)
end

return PitStopController
