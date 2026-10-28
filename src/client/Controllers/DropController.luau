--!strict
-- Post-match drops on screen (Config.Drops): a card left of the podium where your crate falls in, shakes, bursts in its
-- rarity's color and shows the prize ("+N GEMS" when you already had it). The i button opens the odds: every tier's
-- rarity table, the Phantom's chance per tier, and how close your next guaranteed Epic is. A Mythic pull anywhere in
-- the server puts a gold banner and a flash on everyone's screen. Sounds: SoundController, from the same event.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local DropController = {}

local cfg = Config.Drops
local R = cfg.Reveal
local CARD_W = 200
local CARD_H = 250
local CRATE = 104
local PODIUM_HALF = 210 -- HudController's podium is 420 wide and centered

local card: Frame
local tierLabel: TextLabel
local crate: Frame
local burst: Frame
local rarityLabel: TextLabel
local prizeLabel: TextLabel
local extraLabel: TextLabel
local odds: Frame
local oddsRows: Frame
local pityLabel: TextLabel
local banner: TextLabel
local flash: Frame
local shakeUntil = 0
local revealToken = 0

-- Seconds from the drop arriving to the prize showing (SoundController times its sounds to this too).
function DropController.RevealDelay(): number
	return R.Delay + R.DropSeconds + R.ShakeSeconds
end

local function commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- The Phantom's chance from one crate of this tier, as "1 in N".
local function phantomOdds(tier: string): string
	local mythicTotal = 0
	local phantom = 0
	for _, entry in cfg.Pool do
		if entry.Rarity == "Mythic" then
			mythicTotal += entry.Weight
			if entry.Ref == cfg.PhantomRef then
				phantom += entry.Weight
			end
		end
	end
	local chance = (cfg.TierOdds[tier].Mythic or 0) / 100 * (if mythicTotal > 0 then phantom / mythicTotal else 0)
	return if chance > 0 then commas(1 / chance) else "-"
end

local function renderOdds()
	for _, child in oddsRows:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local tiers = { "Bronze", "Silver", "Gold" }
	local colW = 1 / (#tiers + 1)
	local function row(y: number, cells: { string }, colors: { Color3 }?)
		for i, text in cells do
			UI.Label({
				Position = UDim2.new(colW * (i - 1), 0, 0, y),
				Size = UDim2.new(colW, -4, 0, 20),
				Text = text,
				Font = if i == 1 then UI.Font else UI.FontMedium,
				TextColor3 = if colors then colors[i] else UI.White,
				TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			}, oddsRows)
		end
	end
	local head = { "" }
	local headColors = { UI.White }
	for _, tier in tiers do
		table.insert(head, string.upper(tier))
		table.insert(headColors, cfg.TierColors[tier])
	end
	row(0, head, headColors)
	for r, rarity in cfg.Rarities do
		local cells = { string.upper(rarity) }
		local colors = { cfg.Colors[rarity] }
		for _, tier in tiers do
			table.insert(cells, string.format("%s%%", tostring(cfg.TierOdds[tier][rarity])))
			table.insert(colors, UI.White)
		end
		row(r * 24, cells, colors)
	end
	local y = (#cfg.Rarities + 1) * 24 + 6
	local phantomCells = { "PHANTOM" }
	local phantomColors = { cfg.Colors.Mythic }
	for _, tier in tiers do
		table.insert(phantomCells, "1 in " .. phantomOdds(tier))
		table.insert(phantomColors, UI.Muted)
	end
	row(y, phantomCells, phantomColors)
	local profile = State.profile
	local left = cfg.PityEpic - (if profile then profile.pity else 0)
	pityLabel.Text = string.format(cfg.PityLine, math.max(1, left))
end

local function setOdds(open: boolean)
	odds.Visible = open
	if open then
		renderOdds()
	end
end

local function hideCard()
	card.Visible = false
	setOdds(false)
end

-- The reveal: the crate falls in, shakes, bursts, the prize shows; it all goes after HoldSeconds.
local function reveal(payload: Types.DropEventPayload)
	revealToken += 1
	local token = revealToken
	local tier = payload.tier or cfg.DefaultTier
	local rarity = payload.rarity or "Common"
	local color = cfg.Colors[rarity] or UI.White
	tierLabel.Text = cfg.TierNames[tier] or ""
	tierLabel.TextColor3 = cfg.TierColors[tier] or UI.White
	crate.BackgroundColor3 = cfg.TierColors[tier] or UI.White
	crate.Visible = true
	crate.Rotation = 0
	crate.Position = UDim2.new(0.5, 0, 0, -CRATE)
	burst.Visible = false
	rarityLabel.Visible = false
	prizeLabel.Visible = false
	extraLabel.Visible = false
	task.delay(R.Delay, function()
		if token ~= revealToken then
			return
		end
		card.Visible = true
		TweenService:Create(crate, TweenInfo.new(R.DropSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 44) }):Play()
		task.wait(R.DropSeconds)
		if token ~= revealToken then
			return
		end
		shakeUntil = os.clock() + R.ShakeSeconds
		task.wait(R.ShakeSeconds)
		if token ~= revealToken then
			return
		end
		crate.Visible = false
		burst.BackgroundColor3 = color
		burst.Size = UDim2.fromOffset(CRATE * 0.5, CRATE * 0.5)
		burst.BackgroundTransparency = 0.1
		burst.Visible = true
		TweenService:Create(burst, TweenInfo.new(R.BurstSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(CARD_W * 1.4, CARD_W * 1.4), BackgroundTransparency = 1 }):Play()
		rarityLabel.Text = string.upper(rarity)
		rarityLabel.TextColor3 = color
		rarityLabel.Visible = true
		prizeLabel.Text = payload.name or ""
		prizeLabel.Visible = true
		local dupe = payload.duplicateGems
		extraLabel.Text = if dupe then string.format(cfg.DuplicateLine, dupe) else ""
		extraLabel.Visible = dupe ~= nil
		task.wait(R.HoldSeconds)
		if token == revealToken and not odds.Visible then
			hideCard()
		end
	end)
end

-- Someone pulled a Mythic: the gold banner and a flash, timed to land with their reveal.
local function mythicBanner(payload: Types.DropEventPayload)
	local who = string.upper(payload.who or "")
	banner.Text = string.format(if payload.phantom then cfg.MythicBanner else cfg.MythicPrizeBanner, who)
	banner.TextColor3 = cfg.Colors.Legendary
	task.delay(DropController.RevealDelay(), function()
		banner.Visible = true
		flash.BackgroundTransparency = R.FlashAlpha
		flash.Visible = true
		TweenService:Create(flash, TweenInfo.new(R.BurstSeconds * 2), { BackgroundTransparency = 1 }):Play()
		task.wait(R.BannerSeconds)
		banner.Visible = false
		flash.Visible = false
	end)
end

-- A line for the whole server right now (A PHANTOM HAS ENTERED THE MATCH), in the Phantom's glow, no flash.
local function lineBanner(payload: Types.DropEventPayload)
	banner.Text = payload.text or ""
	banner.TextColor3 = Config.Vehicles.Phantom.Glow
	banner.Visible = true
	local text = banner.Text
	task.delay(R.BannerSeconds, function()
		if banner.Text == text then
			banner.Visible = false
		end
	end)
end

local function build()
	local screen = UI.Screen("CrazyFareDrops", 21)
	card = UI.Frame({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -PODIUM_HALF - 16, 0.5, 0),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 0.1,
		ClipsDescendants = true,
		Visible = false,
	}, screen)
	UI.Corner(16, card)
	tierLabel = UI.Label({ Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -56, 0, 22), Text = "", TextXAlignment = Enum.TextXAlignment.Left }, card)
	local info = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Color3.fromRGB(50, 52, 64),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = "i",
	}, card) :: TextButton
	UI.Corner(14, info)
	info.Activated:Connect(function()
		setOdds(not odds.Visible)
	end)
	burst = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 44 + CRATE / 2), BackgroundTransparency = 1, Visible = false, ZIndex = 1 }, card)
	UI.New("UICorner", { CornerRadius = UDim.new(0.5, 0) }, burst)
	crate = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(CRATE, CRATE), BackgroundTransparency = 0, ZIndex = 2 }, card)
	UI.Corner(10, crate)
	UI.Stroke(UI.Black, 3, crate)
	UI.Frame({ Position = UDim2.new(0, 0, 0.32, 0), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = UI.Black, BackgroundTransparency = 0.35, ZIndex = 3 }, crate)
	UI.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.fromScale(0.5, 0.4), Text = "?", TextColor3 = UI.White, ZIndex = 3 }, crate)
	rarityLabel = UI.Label({ Position = UDim2.fromOffset(10, 70), Size = UDim2.new(1, -20, 0, 30), Text = "", Visible = false, ZIndex = 3 }, card)
	prizeLabel = UI.Label({ Position = UDim2.fromOffset(10, 106), Size = UDim2.new(1, -20, 0, 54), Text = "", TextWrapped = true, Visible = false, ZIndex = 3 }, card)
	extraLabel = UI.Label({ Position = UDim2.fromOffset(10, 170), Size = UDim2.new(1, -20, 0, 20), Text = "", TextColor3 = UI.Cash, Font = UI.FontMedium, Visible = false, ZIndex = 3 }, card)

	odds = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 270), BackgroundTransparency = 0.04, Visible = false, ZIndex = 5 }, screen)
	UI.CenterBelowTopbar(odds)
	UI.Corner(16, odds)
	UI.Label({ Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(240, 30), Text = cfg.OddsTitle, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }, odds)
	local close = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Color3.fromRGB(80, 50, 50),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 15,
		TextColor3 = UI.White,
		Text = "X",
		ZIndex = 5,
	}, odds) :: TextButton
	UI.Corner(8, close)
	close.Activated:Connect(function()
		setOdds(false)
	end)
	oddsRows = UI.Frame({ Position = UDim2.fromOffset(20, 50), Size = UDim2.new(1, -40, 0, 170), BackgroundTransparency = 1, ZIndex = 5 }, odds)
	pityLabel = UI.Label({ Position = UDim2.new(0, 20, 1, -46), Size = UDim2.new(1, -40, 0, 16), Text = "", TextColor3 = UI.Warn, Font = UI.FontMedium, ZIndex = 5 }, odds)
	UI.Label({ Position = UDim2.new(0, 20, 1, -26), Size = UDim2.new(1, -40, 0, 14), Text = cfg.OddsNote, TextColor3 = UI.Muted, Font = UI.FontMedium, ZIndex = 5 }, odds)

	banner = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, UI.BelowTopbar(Config.Hud.TopbarHeight + 70)),
		Size = UDim2.fromOffset(760, 54),
		Text = "",
		Font = Config.Title.Logo.Font,
		TextColor3 = cfg.Colors.Legendary,
		Visible = false,
		ZIndex = 6,
	}, screen)
	UI.Stroke(UI.Black, 3, banner)

	local fixed = UI.Screen("CrazyFareDropFlash", 22, true, false)
	flash = UI.Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.White, BackgroundTransparency = 1, Visible = false }, fixed)
end

function DropController.Init()
	build()
	State.DropEvent:Connect(function(payload: Types.DropEventPayload)
		if payload.kind == "Drop" then
			reveal(payload)
		elseif payload.kind == "Mythic" then
			mythicBanner(payload)
		elseif payload.kind == "Banner" then
			lineBanner(payload)
		end
	end)
	-- the next match is on its way: the card goes
	State.RoundChanged:Connect(function(payload: Types.RoundStatePayload)
		if payload.phase == "PreCountdown" or payload.phase == "Countdown" or payload.phase == "Playing" then
			revealToken += 1
			hideCard()
		end
	end)
	State.ProfileChanged:Connect(function()
		if odds.Visible then
			renderOdds()
		end
	end)
end

function DropController.Start()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if now < shakeUntil then
			local left = (shakeUntil - now) / R.ShakeSeconds
			crate.Rotation = math.sin(now * 40) * R.ShakeDegrees * (1 - left * 0.5)
		elseif crate.Rotation ~= 0 then
			crate.Rotation = 0
		end
	end)
end

return DropController
