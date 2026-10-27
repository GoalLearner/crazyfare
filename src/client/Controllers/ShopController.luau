--!strict
-- The shop: Gem packs and the two game passes, plus the one-time Starter Pack card in a player's first sessions.
-- Purchases prompt Roblox's own dialog; the server grants through ProcessReceipt and syncs the profile back.
-- Products with id 0 show as COMING SOON so the layout can be seen before the dashboard ids exist.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local ShopController = {}

local localPlayer = Players.LocalPlayer
local openButton: TextButton
local panel: Frame
local gemsLabel: TextLabel
local packRow: Frame
local passList: Frame
local starterCard: Frame
local isOpen = false
local shopAction: RemoteEvent

local function robuxButton(parent: Instance, text: string, enabled: boolean, size: UDim2): TextButton
	local b = UI.New("TextButton", {
		Size = size,
		BackgroundColor3 = if enabled then Color3.fromRGB(60, 140, 80) else Color3.fromRGB(50, 50, 58),
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

local function promptProduct(id: number)
	if id > 0 then
		MarketplaceService:PromptProductPurchase(localPlayer, id)
	end
end

local function promptPass(id: number)
	if id > 0 then
		MarketplaceService:PromptGamePassPurchase(localPlayer, id)
	end
end

local function renderPacks()
	for _, child in packRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, key in Config.Monetization.ProductOrder do
		local def = Config.Monetization.Products[key]
		if not def then
			continue
		end
		local card = UI.Frame({ Size = UDim2.fromOffset(150, 150), LayoutOrder = i, BackgroundTransparency = 0.3, BackgroundColor3 = Color3.fromRGB(28, 30, 40) }, packRow)
		UI.Corner(12, card)
		UI.Label({ Position = UDim2.fromOffset(8, 14), Size = UDim2.new(1, -16, 0, 40), Text = tostring(def.Gems), TextColor3 = UI.Accent }, card)
		UI.Label({ Position = UDim2.fromOffset(8, 56), Size = UDim2.new(1, -16, 0, 20), Text = "GEMS", TextColor3 = UI.Muted, Font = UI.FontMedium }, card)
		local b = robuxButton(card, if def.Id > 0 then string.format("R$ %d", def.Robux) else "COMING SOON", def.Id > 0, UDim2.new(1, -16, 0, 34))
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -10)
		b.Activated:Connect(function()
			promptProduct(def.Id)
		end)
	end
end

local function renderPasses(profile: Types.ProfilePayload?)
	for _, child in passList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local rows = {
		{ key = "VIP", owned = profile ~= nil and profile.vip },
		{ key = "PitStopPlus", owned = profile ~= nil and profile.pitStopPlus },
	}
	for i, row in rows do
		local def = Config.Monetization.GamePasses[row.key]
		if not def then
			continue
		end
		local frame = UI.Frame({ Size = UDim2.new(1, 0, 0, 58), LayoutOrder = i, BackgroundTransparency = 0.45 }, passList)
		UI.Corner(8, frame)
		UI.Label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(200, 22), Text = string.upper(def.Label), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Warn }, frame)
		UI.Label({ Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -140, 0, 18), Text = def.Effect, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, TextScaled = false, TextSize = 13 }, frame)
		local label = if row.owned then "OWNED" elseif def.Id > 0 then "BUY" else "COMING SOON"
		local b = robuxButton(frame, label, def.Id > 0 and not row.owned, UDim2.fromOffset(110, 32))
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -12, 0.5, 0)
		if def.Id > 0 and not row.owned then
			b.Activated:Connect(function()
				promptPass(def.Id)
			end)
		end
	end
end

local function render()
	local profile = State.profile
	gemsLabel.Text = if profile then string.format("%d GEMS", profile.gems) else ""
	renderPacks()
	renderPasses(profile)
end

local function setOpen(open: boolean)
	isOpen = open
	panel.Visible = open
	if open then
		render()
	end
end

local function updateStarter()
	local profile = State.profile
	local phase = State.GetPhase()
	local show = profile ~= nil and profile.showStarterPack and phase ~= "Playing" and phase ~= "Countdown"
	starterCard.Visible = show
end

local function build()
	local screen = UI.Screen("CrazyFareShop", 16)
	openButton = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24 + Config.Hud.MinimapSize + 10 + (34 + 8) * 2),
		Size = UDim2.fromOffset(Config.Hud.MinimapSize, 34),
		BackgroundColor3 = Color3.fromRGB(70, 110, 190),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = "SHOP",
		Visible = false,
	}, screen) :: TextButton
	UI.Corner(8, openButton)
	openButton.Activated:Connect(function()
		setOpen(not isOpen)
	end)

	panel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 420), BackgroundTransparency = 0.05, Visible = false }, screen)
	UI.CenterBelowTopbar(panel)
	UI.Corner(16, panel)
	UI.Label({ Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(200, 36), Text = "SHOP", TextXAlignment = Enum.TextXAlignment.Left }, panel)
	gemsLabel = UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 18), Size = UDim2.fromOffset(200, 28), Text = "", TextColor3 = UI.Accent, TextXAlignment = Enum.TextXAlignment.Right }, panel)
	local close = robuxButton(panel, "X", true, UDim2.fromOffset(34, 34))
	close.BackgroundColor3 = Color3.fromRGB(80, 50, 50)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 16)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	UI.Label({ Position = UDim2.fromOffset(24, 60), Size = UDim2.fromOffset(300, 20), Text = "GEM PACKS", TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	packRow = UI.Frame({ Position = UDim2.fromOffset(24, 84), Size = UDim2.new(1, -48, 0, 150), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, packRow)
	UI.Label({ Position = UDim2.fromOffset(24, 246), Size = UDim2.fromOffset(300, 20), Text = "PASSES", TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	passList = UI.Frame({ Position = UDim2.fromOffset(24, 270), Size = UDim2.new(1, -48, 0, 130), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, passList)

	-- Starter Pack card (first sessions only)
	local pack = Config.Monetization.Products.StarterPack
	starterCard = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(340, 120), BackgroundTransparency = 0.05, BackgroundColor3 = Color3.fromRGB(40, 32, 60), Visible = false }, screen)
	UI.Corner(14, starterCard)
	UI.Stroke(UI.Warn, 2, starterCard)
	UI.Label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 28), Text = "STARTER PACK", TextColor3 = UI.Warn, TextXAlignment = Enum.TextXAlignment.Left }, starterCard)
	local vehicleName = if pack.Vehicle and Config.Vehicles.Stats[pack.Vehicle] then Config.Vehicles.Stats[pack.Vehicle].DisplayName else ""
	UI.Label({ Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 20), Text = string.format("%d Gems + the %s. One time only.", pack.Gems, vehicleName), TextColor3 = UI.White, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 14 }, starterCard)
	local buy = robuxButton(starterCard, string.format("R$ %d", pack.Robux), true, UDim2.fromOffset(120, 34))
	buy.Position = UDim2.fromOffset(16, 72)
	buy.Activated:Connect(function()
		promptProduct(pack.Id)
	end)
	local later = robuxButton(starterCard, "LATER", true, UDim2.fromOffset(90, 34))
	later.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
	later.Position = UDim2.fromOffset(146, 72)
	later.Activated:Connect(function()
		starterCard.Visible = false
		shopAction:FireServer("DismissStarter")
	end)
end

local function onRound(payload: Types.RoundStatePayload)
	local parked = payload.phase ~= "Playing" and payload.phase ~= "Countdown"
	openButton.Visible = parked
	if not parked and isOpen then
		setOpen(false)
	end
	updateStarter()
end

function ShopController.Init()
	shopAction = Remotes.Get("ShopAction")
	build()
	State.ProfileChanged:Connect(function()
		if isOpen then
			render()
		end
		updateStarter()
	end)
	State.RoundChanged:Connect(onRound)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, purchased: boolean)
		if purchased and userId == localPlayer.UserId then
			shopAction:FireServer("Refresh")
		end
	end)
end

function ShopController.Start() end

return ShopController
