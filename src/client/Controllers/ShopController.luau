--!strict
-- The shop (pay-to-win, owner decision 2026-10-27): tabs for the daily rotating cosmetics (for Gems, Config.DailyShop),
-- game passes, Robux cars, Robux upgrades and Gem packs, and the one-time Starter Pack card in a player's first
-- sessions. Everything sold is permanent (the in-match boosts
-- were cut 2026-10-28). Purchases prompt Roblox's own dialog; the server grants through ProcessReceipt and syncs the
-- profile back. An id of 0 shows COMING SOON, or TEST in Studio, which grants it through the Debug remote.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DailyShop = require(Shared:WaitForChild("DailyShop"))
local Prizes = require(Shared:WaitForChild("Prizes"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)
local PhantomOffer = require(script.Parent.Parent.PhantomOffer)
local SoundController = require(script.Parent.SoundController)

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
local isOpen = false
local tab = M.Tabs[1]
local shopAction: RemoteEvent
local dailyBuy: RemoteEvent
local resetLabel: TextLabel? = nil -- the DAILY tab's countdown, ticked while it shows
local shownDay = 0

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

-- One row: a title in a color, a line of detail, and a button on the right. `inset` leaves room on the left (a swatch).
local function row(order: number, title: string, titleColor: Color3, detail: string, inset: number?): Frame
	local x = 12 + (inset or 0)
	local frame = UI.Frame({ Size = UDim2.new(1, -10, 0, 58), LayoutOrder = order, BackgroundTransparency = 0.45 }, list)
	UI.Corner(8, frame)
	UI.Label({ Position = UDim2.fromOffset(x, 7), Size = UDim2.new(1, -150 - x + 12, 0, 22), Text = string.upper(title), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = titleColor }, frame)
	UI.Label({ Position = UDim2.fromOffset(x, 32), Size = UDim2.new(1, -150 - x + 12, 0, 18), Text = detail, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, TextScaled = false, TextSize = 13 }, frame)
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

-- What a daily item looks like: the paint's color, the trail's colors, or a note to tap for the horn.
local function swatch(frame: Frame, item: Config.Prize)
	local size = Config.DailyShop.SwatchSize
	local ref = item.Ref or ""
	local b = UI.New("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Config.Drops.Colors[item.Rarity] or UI.Accent,
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 20,
		TextColor3 = UI.White,
		TextStrokeTransparency = 0.3,
		Text = "",
		AutoButtonColor = item.Kind == "Horn",
	}, frame) :: TextButton
	UI.Corner(size // 2, b)
	if item.Kind == "Paint" then
		for _, paint in Config.Paint.Colors do
			if paint.Name == ref then
				b.BackgroundColor3 = paint.Color
				b.Text = if paint.Material then Config.Paint.MaterialMark else ""
			end
		end
	elseif item.Kind == "Trail" then
		local def = Config.Cosmetics.Trails[ref]
		if def then
			b.BackgroundColor3 = UI.White
			local points: { ColorSequenceKeypoint } = {}
			for i, color in def.Colors do
				table.insert(points, ColorSequenceKeypoint.new(if #def.Colors > 1 then (i - 1) / (#def.Colors - 1) else 0, color))
			end
			if #points == 1 then
				table.insert(points, ColorSequenceKeypoint.new(1, def.Colors[1]))
			end
			UI.New("UIGradient", { Color = ColorSequence.new(points) }, b)
		end
	elseif item.Kind == "Horn" then
		b.Text = "\u{266A}"
		b.Activated:Connect(function()
			SoundController.PlayHorn(ref)
		end)
	end
end

local function renderDaily(profile: Types.ProfilePayload?)
	local cfg = Config.DailyShop
	local now = workspace:GetServerTimeNow()
	shownDay = DailyShop.Day(now)
	resetLabel = UI.Label({ Size = UDim2.new(1, -10, 0, 20), LayoutOrder = 0, Text = string.format(cfg.ResetLine, UI.FormatTime(DailyShop.SecondsLeft(now))), TextColor3 = UI.Warn, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 14 }, list)
	local inventory = if profile then profile.inventory else nil
	local gems = if profile then profile.gems else 0
	for i, item in DailyShop.Items(shownDay) do
		local ownedKind = if inventory then inventory[item.Kind .. "s"] else nil
		local owned = ownedKind ~= nil and (ownedKind[item.Ref or ""] or 0) > 0
		local price = DailyShop.Price(item)
		local detail = string.format("%s  ·  %s", cfg.Kinds[item.Kind] or item.Kind, string.upper(item.Rarity))
		if item.Kind == "Horn" then
			detail ..= "  ·  " .. cfg.HornHint
		end
		local color = Config.Drops.Colors[item.Rarity] or UI.Accent
		local frame = row(i, Prizes.Name(item), color:Lerp(UI.White, 0.3), detail, cfg.SwatchSize + 10)
		swatch(frame, item)
		rightButton(frame, if owned then cfg.OwnedLabel else string.format(cfg.PriceLabel, price), not owned and gems >= price, function()
			dailyBuy:FireServer(item.Id)
		end)
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
		-- a Mythic car: how rare it is, and on sale only inside its offer window
		local mythic = stats.Mythic == true
		local onSale = not mythic or PhantomOffer.SecondsLeft() > 0
		if mythic then
			detail = string.format("%s  ·  %s  ·  Top speed %d.", PhantomOffer.OwnersText(), PhantomOffer.StatusText(), stats.TopSpeed)
		end
		local frame = row(order, stats.DisplayName, if mythic then Config.Vehicles.Phantom.Glow else stats.Color:Lerp(UI.White, 0.35), detail)
		local price = if onSale then priceText(productId, M.VehicleRobux[id] or 0) else Config.Vehicles.Phantom.DropOnlyButton
		rightButton(frame, if owned then "OWNED" else price, not owned and onSale and buyable(productId), function()
			buy(id, productId, false)
		end)
	end
end

local function renderUpgrades()
	for i, key in M.BoostOrder do
		local def = M.Boosts[key]
		if not def then
			continue
		end
		local frame = row(i, def.Label, def.Color, def.Effect)
		rightButton(frame, priceText(def.Id, def.Robux), buyable(def.Id), function()
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
		local frame = row(i, def.Label, UI.Accent, "Gems buy cars, upgrades, paint and the daily items.")
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
	resetLabel = nil
	if tab == "DAILY" then
		renderDaily(profile)
	elseif tab == "PASSES" then
		renderPasses(profile)
	elseif tab == "CARS" then
		renderCars(profile)
	elseif tab == "UPGRADES" then
		renderUpgrades()
	else
		renderGems()
	end
	list.CanvasPosition = Vector2.zero
end

local updateStarter: () -> ()

local function setOpen(open: boolean)
	isOpen = open
	panel.Visible = open
	if open then
		render()
	end
	updateStarter()
end

function updateStarter()
	local profile = State.profile
	local phase = State.GetPhase()
	-- the depot only: anywhere else it sits on the podium (and its drop crate) or the Pit Stop panel, and never over the
	-- shop panel itself
	local show = profile ~= nil and profile.showStarterPack and phase == "Waiting" and State.sessionState ~= "Title" and not isOpen
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
	local tabWidth = (panel.Size.X.Offset - 48 - 8 * (#M.Tabs - 1)) // #M.Tabs
	for i, name in M.Tabs do
		local b = button(tabRow, name, true, UDim2.fromOffset(tabWidth, 34), TAB_OFF)
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
end

-- Parked: between rounds, or not driving at all (on foot, in the depot).
local function onRound(payload: Types.RoundStatePayload)
	local parked = (payload.phase ~= "Playing" and payload.phase ~= "Countdown") or (State.sessionState ~= "Driver" and State.sessionState ~= "")
	openButton.Visible = parked
	if not parked and isOpen then
		setOpen(false)
	end
	updateStarter()
end

function ShopController.Init()
	shopAction = Remotes.Get("ShopAction")
	dailyBuy = Remotes.Get("DailyBuy")
	build()
	State.ProfileChanged:Connect(function()
		if isOpen then
			render()
		end
		updateStarter()
	end)
	PhantomOffer.OnOwnersChanged(function()
		if isOpen then
			render()
		end
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
	-- the DAILY tab's countdown ticks, and a new day brings new items while it's open
	local nextTick = 0
	RunService.Heartbeat:Connect(function()
		local label = resetLabel
		if not isOpen or not label or os.clock() < nextTick then
			return
		end
		nextTick = os.clock() + 1
		local now = workspace:GetServerTimeNow()
		if DailyShop.Day(now) ~= shownDay then
			render()
			return
		end
		label.Text = string.format(Config.DailyShop.ResetLine, UI.FormatTime(DailyShop.SecondsLeft(now)))
	end)
end

return ShopController
