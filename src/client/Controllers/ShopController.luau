--!strict
-- The shop (pay-to-win, owner decision 2026-10-27): tabs for game passes, Robux cars, in-match boosts and Gem packs,
-- the one-time Starter Pack card in a player's first sessions, and a quick-buy strip on the HUD while you drive a round
-- (Config.Monetization.QuickBuy). Purchases prompt Roblox's own dialog; the server grants through ProcessReceipt and
-- syncs the profile back. An id of 0 shows COMING SOON, or TEST in Studio, which grants it through the Debug remote.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local ShopController = {}

local BUY_COLOR = Color3.fromRGB(60, 140, 80)
local OFF_COLOR = Color3.fromRGB(50, 50, 58)
local TAB_ON = Color3.fromRGB(70, 110, 190)
local TAB_OFF = Color3.fromRGB(36, 38, 48)

local M = Config.Monetization
local isStudio = RunService:IsStudio()
local localPlayer = Players.LocalPlayer
local openButton: TextButton
local panel: Frame
local gemsLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local list: ScrollingFrame
local starterCard: Frame
local quickStrip: Frame
local quickButtons: { [string]: TextButton } = {}
local isOpen = false
local tab = M.Tabs[1]
local shopAction: RemoteEvent

local function button(parent: Instance, text: string, enabled: boolean, size: UDim2, color: Color3?): TextButton
	local b = UI.New("TextButton", {
		Size = size,
		BackgroundColor3 = if enabled then color or BUY_COLOR else OFF_COLOR,
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

-- Something with a Robux id can be bought; with id 0 only Studio's TEST grant works.
local function buyable(id: number): boolean
	return id > 0 or isStudio
end

local function priceText(id: number, robux: number): string
	if id > 0 then
		return string.format("R$ %d", robux)
	end
	return if isStudio then string.format("TEST %d", robux) else "COMING SOON"
end

-- Prompt Roblox's purchase dialog (or, in Studio with no id yet, grant it as if bought).
local function buy(key: string, id: number, isPass: boolean)
	if id > 0 then
		if isPass then
			MarketplaceService:PromptGamePassPurchase(localPlayer, id)
		else
			MarketplaceService:PromptProductPurchase(localPlayer, id)
		end
	elseif isStudio then
		Remotes.Get("Debug"):FireServer("Grant", key)
	end
end

local function clearList()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- One row: a title in a color, a line of detail, and a button on the right.
local function row(order: number, title: string, titleColor: Color3, detail: string): Frame
	local frame = UI.Frame({ Size = UDim2.new(1, -10, 0, 58), LayoutOrder = order, BackgroundTransparency = 0.45 }, list)
	UI.Corner(8, frame)
	UI.Label({ Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -150, 0, 22), Text = string.upper(title), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = titleColor }, frame)
	UI.Label({ Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -150, 0, 18), Text = detail, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, TextScaled = false, TextSize = 13 }, frame)
	return frame
end

local function rightButton(frame: Frame, text: string, enabled: boolean, onBuy: (() -> ())?)
	local b = button(frame, text, enabled, UDim2.fromOffset(120, 34))
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -12, 0.5, 0)
	if enabled and onBuy then
		b.Activated:Connect(onBuy)
	end
end

local function renderPasses(profile: Types.ProfilePayload?)
	for i, key in M.PassOrder do
		local def = M.GamePasses[key]
		if not def then
			continue
		end
		local owned = profile ~= nil and profile.passes ~= nil and profile.passes[key] == true
		local frame = row(i, def.Label, UI.Warn, def.Effect)
		rightButton(frame, if owned then "OWNED" else priceText(def.Id, def.Robux), not owned and buyable(def.Id), function()
			buy(key, def.Id, true)
		end)
	end
end

local function renderCars(profile: Types.ProfilePayload?)
	local order = 0
	for _, id in Config.Vehicles.Order do
		local productId = M.VehicleProducts[id]
		local stats = Config.Vehicles.Stats[id]
		if productId == nil or not stats then
			continue
		end
		order += 1
		local owned = profile ~= nil and profile.owned[id] == true
		local detail = string.format("%s  Top speed %d.", stats.Description, stats.TopSpeed)
		if not stats.RobuxOnly then
			detail ..= string.format(" Or %d Gems in the garage.", stats.GemPrice)
		end
		local frame = row(order, stats.DisplayName, stats.Color:Lerp(UI.White, 0.35), detail)
		rightButton(frame, if owned then "OWNED" else priceText(productId, M.VehicleRobux[id] or 0), not owned and buyable(productId), function()
			buy(id, productId, false)
		end)
	end
end

local function renderBoosts()
	for i, key in M.BoostOrder do
		local def = M.Boosts[key]
		if not def then
			continue
		end
		-- the shop opens between rounds: in-round boosts are bought from the strip on the HUD while you drive
		local anytime = key == "MaxUpgrades"
		local frame = row(i, def.Label, def.Color, def.Effect .. (if anytime then "" else ". Buy it while you drive."))
		rightButton(frame, if anytime then priceText(def.Id, def.Robux) else "IN A ROUND", anytime and buyable(def.Id), function()
			buy(key, def.Id, false)
		end)
	end
end

local function renderGems()
	for i, key in M.ProductOrder do
		local def = M.Products[key]
		if not def then
			continue
		end
		local frame = row(i, def.Label, UI.Accent, "Gems buy cars, upgrades and paint.")
		rightButton(frame, priceText(def.Id, def.Robux), buyable(def.Id), function()
			buy(key, def.Id, false)
		end)
	end
end

local function render()
	local profile = State.profile
	gemsLabel.Text = if profile then string.format("%d GEMS", profile.gems) else ""
	for name, b in tabButtons do
		b.BackgroundColor3 = if name == tab then TAB_ON else TAB_OFF
	end
	clearList()
	if tab == "PASSES" then
		renderPasses(profile)
	elseif tab == "CARS" then
		renderCars(profile)
	elseif tab == "BOOSTS" then
		renderBoosts()
	else
		renderGems()
	end
	list.CanvasPosition = Vector2.zero
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
	-- the depot and the podium only: during a round's setup or the Pit Stop it would sit on the Pit Stop panel
	local show = profile ~= nil and profile.showStarterPack and (phase == "Waiting" or phase == "MatchEnd") and State.sessionState ~= "Title"
	starterCard.Visible = show
end

-- The quick-buy strip: while you drive a live round. A boost greys out when it would do nothing (a full tank, no
-- passenger or a healthy one), so a tap never turns into the Gem fallback by accident.
local function updateQuick()
	local driving = State.sessionState == "Driver" and State.GetPhase() == "Playing" and State.chassis ~= nil
	local any = false
	for key, b in quickButtons do
		local def = M.Boosts[key]
		local can = buyable(def.Id)
		b.Visible = can
		any = any or can
		local useful = true
		if key == "NitroRefill" then
			useful = State.boostTank < State.boostTankMax - 0.05
		elseif key == "PatchUp" then
			useful = State.fare ~= nil and State.hp < State.maxHp
		end
		b.Active = useful
		b.AutoButtonColor = useful
		b.BackgroundTransparency = if useful then 0.1 else 0.55
	end
	quickStrip.Visible = driving and any
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

	panel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 470), BackgroundTransparency = 0.05, Visible = false }, screen)
	UI.CenterBelowTopbar(panel)
	UI.Corner(16, panel)
	UI.Label({ Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(200, 36), Text = "SHOP", TextXAlignment = Enum.TextXAlignment.Left }, panel)
	gemsLabel = UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 18), Size = UDim2.fromOffset(200, 28), Text = "", TextColor3 = UI.Accent, TextXAlignment = Enum.TextXAlignment.Right }, panel)
	local close = button(panel, "X", true, UDim2.fromOffset(34, 34), Color3.fromRGB(80, 50, 50))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 16)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local tabRow = UI.Frame({ Position = UDim2.fromOffset(24, 60), Size = UDim2.new(1, -48, 0, 34), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, tabRow)
	for i, name in M.Tabs do
		local b = button(tabRow, name, true, UDim2.fromOffset(134, 34), TAB_OFF)
		b.LayoutOrder = i
		b.Activated:Connect(function()
			tab = name
			render()
		end)
		tabButtons[name] = b
	end

	list = UI.New("ScrollingFrame", {
		Position = UDim2.fromOffset(24, 106),
		Size = UDim2.new(1, -40, 1, -122),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, panel) :: ScrollingFrame
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	-- Starter Pack card (first sessions only)
	local pack = M.Products.StarterPack
	starterCard = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(340, 120), BackgroundTransparency = 0.05, BackgroundColor3 = Color3.fromRGB(40, 32, 60), Visible = false }, screen)
	UI.Corner(14, starterCard)
	UI.Stroke(UI.Warn, 2, starterCard)
	UI.Label({ Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 28), Text = "STARTER PACK", TextColor3 = UI.Warn, TextXAlignment = Enum.TextXAlignment.Left }, starterCard)
	local vehicleName = if pack.Vehicle and Config.Vehicles.Stats[pack.Vehicle] then Config.Vehicles.Stats[pack.Vehicle].DisplayName else ""
	UI.Label({ Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 20), Text = string.format("%d Gems, the %s, upgrades to level %d. Once.", pack.Gems, vehicleName, pack.UpgradeLevel or 0), TextColor3 = UI.White, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 14 }, starterCard)
	local packBuy = button(starterCard, priceText(pack.Id, pack.Robux), buyable(pack.Id), UDim2.fromOffset(120, 34))
	packBuy.Position = UDim2.fromOffset(16, 72)
	packBuy.Activated:Connect(function()
		buy("StarterPack", pack.Id, false)
	end)
	local later = button(starterCard, "LATER", true, UDim2.fromOffset(90, 34), OFF_COLOR)
	later.Position = UDim2.fromOffset(146, 72)
	later.Activated:Connect(function()
		starterCard.Visible = false
		shopAction:FireServer("DismissStarter")
	end)

	-- Quick-buy strip: in-round boosts, one tap to Roblox's purchase dialog. Left middle on a computer; on a phone the
	-- left holds HOP and HONK, so a shorter strip sits under the minimap (the side buttons are hidden mid-round)
	local quick = UI.Screen("CrazyFareQuickBuy", 12)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local keys: { string } = if touch then M.QuickBuyTouch else M.QuickBuy
	local height = if touch then 30 else 39 -- shorter on a phone: the strip must end above the BOOST pad
	quickStrip = UI.Frame({
		AnchorPoint = if touch then Vector2.new(1, 0) else Vector2.new(0, 0.5),
		Position = if touch then UDim2.new(1, -24, 0, 24 + Config.Hud.MinimapSize + 10) else UDim2.new(0, 24, 0.5, 0),
		Size = UDim2.fromOffset(132, #keys * (height + 5)),
		BackgroundTransparency = 1,
		Visible = false,
	}, quick)
	UI.New("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, quickStrip)
	for i, key in keys do
		local def = M.Boosts[key]
		if not def then
			continue
		end
		local b = button(quickStrip, "", true, UDim2.fromOffset(132, height), Color3.fromRGB(24, 26, 34))
		b.LayoutOrder = i
		UI.Stroke(def.Color, 2, b)
		UI.Label({ Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0.55, -2), Text = def.Label, TextColor3 = def.Color, TextXAlignment = Enum.TextXAlignment.Left }, b)
		UI.Label({ Position = UDim2.new(0, 8, 0.55, 1), Size = UDim2.new(1, -16, 0.38, 0), Text = priceText(def.Id, def.Robux), TextColor3 = UI.White, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, b)
		b.Activated:Connect(function()
			if b.Active then
				buy(key, def.Id, false)
			end
		end)
		quickButtons[key] = b
	end
end

-- Parked: between rounds, or not driving at all (on foot, in the depot).
local function onRound(payload: Types.RoundStatePayload)
	local parked = (payload.phase ~= "Playing" and payload.phase ~= "Countdown") or (State.sessionState ~= "Driver" and State.sessionState ~= "")
	openButton.Visible = parked
	if not parked and isOpen then
		setOpen(false)
	end
	updateStarter()
	updateQuick()
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
	State.SessionChanged:Connect(function()
		local round = State.round
		if round then
			onRound(round)
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, purchased: boolean)
		if purchased and userId == localPlayer.UserId then
			shopAction:FireServer("Refresh")
		end
	end)
end

function ShopController.Start()
	RunService.Heartbeat:Connect(updateQuick)
end

return ShopController
