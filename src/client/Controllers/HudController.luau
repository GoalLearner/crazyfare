--!strict
-- The HUD: cash + quota, round timer, fare card, combo, boost tank, item slot, speed, center messages,
-- destination arrow, podium with gems and the rematch vote. Reads State; the only thing it sends is RematchVote.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Money = require(Shared:WaitForChild("Money"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local VecUtil = require(Shared:WaitForChild("VecUtil"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local HudController = {}

local screen: ScreenGui
local cashLabel: TextLabel
local quotaBar: UI.Bar
local quotaLabel: TextLabel
local timerLabel: TextLabel
local phaseLabel: TextLabel
local arrow: TextLabel
local arrowDistance: TextLabel

local fareCard: Frame
local fareTier: TextLabel
local fareValue: TextLabel
local fareTimer: UI.Bar
local fareHp: UI.Bar
local fareHpLabel: TextLabel

local comboLabel: TextLabel
local comboBar: UI.Bar
local boostBar: UI.Bar
local speedLabel: TextLabel
local itemSlot: Frame
local itemLabel: TextLabel

local message: TextLabel
local subMessage: TextLabel
local messageUntil = 0
local lastCountdownShown = -1

local podium: Frame
local podiumRows: Frame
local podiumFooter: TextLabel
local podiumTitle: TextLabel
local rematchButton: TextButton
local gemsLabel: TextLabel

local function tierColor(tier: string): Color3
	local def = Config.Fares.Tiers[tier]
	return if def then def.Color else UI.White
end

local function showMessage(text: string, color: Color3, seconds: number, sub: string?)
	message.Text = text
	message.TextColor3 = color
	message.Visible = true
	subMessage.Text = sub or ""
	subMessage.Visible = sub ~= nil and sub ~= ""
	messageUntil = os.clock() + seconds
	message.Size = UDim2.fromScale(0.5, 0.05)
	TweenService:Create(message, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(0.6, 0.11),
	}):Play()
end

local function build()
	screen = UI.Screen("CrazyFareHud", 10)

	-- Cash + quota (top-left)
	local cashBox = UI.Frame({ Position = UDim2.fromOffset(24, 76), Size = UDim2.fromOffset(220, 92), BackgroundTransparency = 1 }, screen)
	cashLabel = UI.Label({ Size = UDim2.fromOffset(220, 56), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Cash, Text = "$0" }, cashBox)
	quotaBar = UI.Bar({ Position = UDim2.fromOffset(0, 62), Size = UDim2.fromOffset(220, 10) }, UI.Cash, cashBox)
	quotaLabel = UI.Label({ Position = UDim2.fromOffset(0, 74), Size = UDim2.fromOffset(220, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "" }, cashBox)
	gemsLabel = UI.Label({ Position = UDim2.fromOffset(0, 94), Size = UDim2.fromOffset(220, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Accent, Font = UI.FontMedium, Text = "" }, cashBox)

	-- Timer + phase (top-center)
	timerLabel = UI.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), Size = UDim2.fromOffset(160, 44), Text = "4:00" }, screen)
	phaseLabel = UI.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66), Size = UDim2.fromOffset(360, 22), TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "" }, screen)

	-- Destination arrow (under the timer)
	arrow = UI.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(44, 44), Text = "▲", TextColor3 = UI.Accent, Visible = false }, screen)
	arrowDistance = UI.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 138), Size = UDim2.fromOffset(120, 20), TextColor3 = UI.Accent, Font = UI.FontMedium, Text = "", Visible = false }, screen)

	-- Fare card (bottom-right)
	fareCard = UI.Frame({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Size = UDim2.fromOffset(240, 118), Visible = false }, screen)
	UI.Corner(10, fareCard)
	fareTier = UI.Label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(120, 22), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.FontMedium, Text = "SHORT" }, fareCard)
	fareValue = UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 4), Size = UDim2.fromOffset(100, 34), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Cash, Text = "$10" }, fareCard)
	fareTimer = UI.Bar({ Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -24, 0, 12) }, UI.Warn, fareCard)
	fareHp = UI.Bar({ Position = UDim2.fromOffset(12, 74), Size = UDim2.new(1, -24, 0, 14) }, UI.Danger, fareCard)
	fareHpLabel = UI.Label({ Position = UDim2.fromOffset(12, 92), Size = UDim2.new(1, -24, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "PASSENGER" }, fareCard)

	-- Combo + boost + speed (bottom-center)
	local center = UI.Frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(260, 90), BackgroundTransparency = 1 }, screen)
	comboLabel = UI.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(200, 40), TextColor3 = UI.Warn, Text = "" }, center)
	comboBar = UI.Bar({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(200, 8) }, UI.Warn, center)
	boostBar = UI.Bar({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.fromOffset(200, 8) }, UI.Accent, center)
	speedLabel = UI.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 68), Size = UDim2.fromOffset(120, 22), TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "0" }, center)

	-- Item slot (bottom-left)
	itemSlot = UI.Frame({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -24), Size = UDim2.fromOffset(120, 120) }, screen)
	UI.Corner(14, itemSlot)
	UI.Stroke(Color3.fromRGB(60, 60, 70), 2, itemSlot)
	itemLabel = UI.Label({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), Text = "" }, itemSlot)
	UI.Label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(100, 16), TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "Q" }, itemSlot)

	-- Center messages
	message = UI.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromScale(0.6, 0.11), Text = "", Visible = false }, screen)
	subMessage = UI.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromScale(0.5, 0.04), Text = "", TextColor3 = UI.Muted, Font = UI.FontMedium, Visible = false }, screen)

	-- Podium
	podium = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 320), BackgroundTransparency = 0.1, Visible = false }, screen)
	UI.Corner(16, podium)
	podiumTitle = UI.Label({ Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 40), Text = "ROUND OVER" }, podium)
	podiumRows = UI.Frame({ Position = UDim2.fromOffset(20, 66), Size = UDim2.new(1, -40, 1, -110), BackgroundTransparency = 1 }, podium)
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, podiumRows)
	podiumFooter = UI.Label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -40, 0, 22), TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "" }, podium)
	rematchButton = UI.New("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(180, 38),
		BackgroundColor3 = Color3.fromRGB(60, 140, 80),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 18,
		TextColor3 = UI.White,
		Text = "REMATCH",
		Visible = false,
	}, podium) :: TextButton
	UI.Corner(10, rematchButton)
	rematchButton.Activated:Connect(function()
		Remotes.Get("RematchVote"):FireServer()
		rematchButton.Text = "READY"
		rematchButton.BackgroundColor3 = Color3.fromRGB(40, 70, 48)
	end)
end

local function fillPodium(results: { Types.PodiumEntry })
	for _, child in podiumRows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, entry in results do
		local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 36), LayoutOrder = i, BackgroundTransparency = if i == 1 then 0.2 else 0.6, BackgroundColor3 = if i == 1 then Color3.fromRGB(60, 50, 20) else UI.Panel }, podiumRows)
		UI.Corner(8, row)
		UI.Label({ Position = UDim2.fromOffset(10, 4), Size = UDim2.fromOffset(30, 28), Text = tostring(i), TextColor3 = if i == 1 then UI.Warn else UI.Muted }, row)
		UI.Label({ Position = UDim2.fromOffset(48, 4), Size = UDim2.fromOffset(110, 28), Text = entry.name, TextXAlignment = Enum.TextXAlignment.Left }, row)
		UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 4), Size = UDim2.fromOffset(70, 28), Text = UI.Money(entry.cash), TextColor3 = UI.Cash, TextXAlignment = Enum.TextXAlignment.Right }, row)
		UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 8), Size = UDim2.fromOffset(60, 20), Text = string.format("%d fares", entry.fares), TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Right }, row)
		if entry.gems then
			UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -152, 0, 8), Size = UDim2.fromOffset(70, 20), Text = string.format("+%d gems", entry.gems), TextColor3 = UI.Accent, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Right }, row)
		end
	end
end

local function onRound(payload: Types.RoundStatePayload)
	local isMatchEnd = payload.phase == "MatchEnd"
	if (payload.phase == "RoundEnd" or isMatchEnd) and payload.results then
		fillPodium(payload.results)
		podiumTitle.Text = if isMatchEnd then "MATCH OVER" else string.format("ROUND %d OVER", payload.round)
		rematchButton.Visible = isMatchEnd
		if isMatchEnd and rematchButton.Text == "READY" and (payload.votes or 0) == 0 then
			rematchButton.Text = "REMATCH"
			rematchButton.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
		end
		podium.Visible = true
		local winner = payload.results[1]
		if winner and isMatchEnd then
			showMessage(string.upper(winner.name) .. " WINS", UI.Warn, 3)
		end
	else
		podium.Visible = false
	end
	if payload.phase == "PreCountdown" and payload.round == 1 then
		rematchButton.Text = "REMATCH"
		rematchButton.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
	end
	if payload.phase == "PreCountdown" then
		showMessage("READ THE BOARD", UI.Accent, Config.Round.PreCountdownSeconds)
		lastCountdownShown = -1
	elseif payload.phase == "Playing" then
		showMessage("GO!", UI.Cash, 0.9)
	end
end

local function onFare(payload: Types.FareEventPayload)
	if payload.kind == "Delivered" then
		local tip = payload.tip or 0
		local combo = payload.combo or 1
		local parts = {}
		if tip > 0 then
			table.insert(parts, "TIP " .. UI.Money(tip))
		end
		if combo > 1.01 then
			table.insert(parts, string.format("x%.1f", combo))
		end
		if payload.line then
			table.insert(parts, payload.line)
		end
		showMessage("+" .. UI.Money(payload.payout or 0), UI.Cash, Config.Hud.PayoutPunchSeconds, if #parts > 0 then table.concat(parts, "  ·  ") else nil)
	elseif payload.kind == "Bailed" then
		local reason = if payload.reason == "timeout" then "TIME'S UP" elseif payload.reason == "pedestrian" then "WATCH THE ROAD!" else "PASSENGER BAILED"
		showMessage(reason, UI.Danger, Config.Hud.MessageSeconds, "-" .. UI.Money(payload.base or 0) .. " fare")
	elseif payload.kind == "Expired" then
		showMessage("TIME'S UP", UI.Warn, Config.Hud.MessageSeconds, "no tip now, still deliver them")
	elseif payload.kind == "HunterBonus" then
		showMessage("+" .. UI.Money(payload.payout or 0), UI.Danger, Config.Hud.PayoutPunchSeconds, "HUNTER BONUS  ·  " .. (payload.line or ""))
	elseif payload.kind == "Taken" then
		showMessage("TAKEN", UI.Warn, 0.8)
	elseif payload.kind == "Hurt" and payload.source == "crash" then
		showMessage(payload.line or "OW!", UI.Danger, Config.Hud.CrashMessageSeconds, string.format("-%d HP", payload.amount or 0))
	elseif payload.kind == "Claimed" then
		local def = Config.Fares.Tiers[payload.tier or ""]
		showMessage((if def then def.Label else "FARE") .. " TRIP", tierColor(payload.tier or ""), 1.0, "Drop them at the beacon")
	end
end

local function onItem(payload: Types.ItemEventPayload)
	if payload.kind == "HitConfirm" then
		showMessage(if payload.item == "Shield" then "BLOCKED" else "SPLAT!", UI.Danger, 0.8, payload.attacker)
	elseif payload.kind == "ShieldUp" then
		showMessage("SHIELD UP", UI.Accent, 0.9)
	elseif payload.kind == "ShieldBreak" then
		showMessage("SHIELD BROKE", UI.Accent, 0.9)
	elseif payload.kind == "Seatbelt" then
		showMessage("SEATBELT ON", UI.Cash, 0.9, string.format("%d s immune", math.round(payload.seconds or 0)))
	elseif payload.kind == "Oil" then
		showMessage("OIL!", UI.Warn, 1.2, "no steering")
	elseif payload.kind == "Immune" then
		showMessage("NO EFFECT", UI.Accent, 0.8, "this ride shrugs it off")
	elseif payload.kind == "Granted" and payload.item and payload.item ~= "" then
		local def = Config.Items.Pool[payload.item]
		if def then
			showMessage(string.upper(def.DisplayName), def.Color, 0.8)
		end
	end
end

local function update()
	local now = workspace:GetServerTimeNow()
	local round = State.round
	local phase = State.GetPhase()

	cashLabel.Text = UI.Money(State.cash)
	local quota = if round then round.quota else Money.Cents(Config.Round.Quotas[1])
	UI.SetBar(quotaBar, if quota > 0 then State.cash / quota else 0)
	quotaLabel.Text = "QUOTA " .. UI.Money(quota)

	-- Timer / phase text
	if round and phase == "Playing" then
		timerLabel.Text = UI.FormatTime(round.endsAt - now)
		timerLabel.TextColor3 = if round.endsAt - now < 30 then UI.Danger else UI.White
		phaseLabel.Text = ""
	elseif round and phase == "Countdown" then
		local remaining = round.endsAt - now
		local n = math.ceil(remaining)
		timerLabel.Text = UI.FormatTime(Config.Round.CapSeconds)
		phaseLabel.Text = ""
		if n ~= lastCountdownShown and n >= 1 then
			lastCountdownShown = n
			showMessage(tostring(n), UI.White, 1.1)
		end
	elseif phase == "PreCountdown" then
		timerLabel.Text = UI.FormatTime(Config.Round.CapSeconds)
		phaseLabel.Text = "ROUND " .. (if round then round.round else 1) .. "  ·  FIRST TO " .. UI.Money(quota)
	elseif phase == "RoundEnd" and round then
		timerLabel.Text = ""
		phaseLabel.Text = ""
		podiumFooter.Text = "Pit stop in " .. math.max(0, math.ceil(round.endsAt - now))
	elseif phase == "PitStop" and round then
		timerLabel.Text = "PIT STOP"
		phaseLabel.Text = "NEXT: ROUND " .. (round.round + 1) .. "  ·  FIRST TO " .. UI.Money(Money.Cents(Config.Round.Quotas[math.min(round.round + 1, #Config.Round.Quotas)]))
	elseif phase == "MatchEnd" and round then
		timerLabel.Text = ""
		phaseLabel.Text = ""
		podiumFooter.Text = string.format("Rematch %d/%d  ·  next match in %d", round.votes or 0, round.voters or 0, math.max(0, math.ceil(round.endsAt - now)))
	else
		timerLabel.Text = ""
		phaseLabel.Text = "WAITING FOR PLAYERS"
	end

	-- Fare card
	local fare = State.fare
	if fare and phase == "Playing" then
		fareCard.Visible = true
		fareTier.Text = (Config.Fares.Tiers[fare.tier] or Config.Fares.Tiers.Green).Label
		fareTier.TextColor3 = tierColor(fare.tier)
		fareValue.Text = UI.Money(fare.base)
		local total = math.max(0.01, fare.deadline - fare.startedAt)
		local remaining = VecUtil.Clamp01((fare.deadline - now) / total)
		UI.SetBar(fareTimer, remaining, if remaining < 0.25 then UI.Danger else UI.Warn)
		local hpFrac = if State.maxHp > 0 then State.hp / State.maxHp else 1
		UI.SetBar(fareHp, hpFrac, if hpFrac > 0.5 then UI.Cash else (if hpFrac > 0.25 then UI.Warn else UI.Danger))
		fareHpLabel.Text = string.format("PASSENGER %d/%d", math.round(State.hp), State.maxHp)

		-- Destination arrow relative to the camera heading
		local ch = State.chassis
		local camera = workspace.CurrentCamera
		if ch and camera then
			local toDest = VecUtil.Flat(fare.destination - ch.Position)
			local dist = toDest.Magnitude
			local camLook = VecUtil.FlatUnit(camera.CFrame.LookVector)
			local dir = VecUtil.FlatUnit(toDest, camLook)
			local angle = math.atan2(camLook:Cross(dir).Y, camLook:Dot(dir))
			arrow.Rotation = -math.deg(angle)
			arrow.Visible = false -- the 3D arrow over the cab (EffectsController) replaced this
			arrowDistance.Visible = false
			arrowDistance.Text = string.format("%d", math.round(dist))
			arrow.TextColor3 = if dist <= Config.Fares.DeliverRadius then UI.Cash else UI.Accent
		end
	else
		fareCard.Visible = false
		arrow.Visible = false
		arrowDistance.Visible = false
	end

	-- Combo
	local combo = State.combo
	local maxSteps = (Config.Combo.Max - 1) / Config.Combo.Step
	local steps = (combo - 1) / Config.Combo.Step
	comboLabel.Text = if combo > 1.01 then string.format("x%.1f", combo) else ""
	UI.SetBar(comboBar, if maxSteps > 0 then steps / maxSteps else 0)
	comboBar.back.Visible = combo > 1.01

	-- Boost tank + speed
	UI.SetBar(boostBar, if State.boostTankMax > 0 then State.boostTank / State.boostTankMax else 0, if State.boosting then UI.Warn else UI.Accent)
	local me = State.GetSelfSnap()
	gemsLabel.Text = string.format("LV %d  ·  %d GEMS", if me then me.level else 1, State.gems)
	speedLabel.Text = string.format("%d", math.round(State.speed))

	-- Item slot
	local def = Config.Items.Pool[State.item]
	if def then
		itemLabel.Text = string.upper(def.DisplayName)
		itemLabel.TextColor3 = def.Color
		itemSlot.BackgroundTransparency = 0.1
	else
		itemLabel.Text = ""
		itemSlot.BackgroundTransparency = 0.5
	end

	-- Messages
	if message.Visible and os.clock() >= messageUntil then
		message.Visible = false
		subMessage.Visible = false
	end
end

function HudController.Init()
	build()
	State.RoundChanged:Connect(onRound)
	State.FareEvent:Connect(onFare)
	State.ItemEvent:Connect(onItem)
	State.Notice:Connect(function(text: string)
		showMessage(text, UI.Accent, 2.2)
	end)
end

function HudController.Start()
	RunService.RenderStepped:Connect(update)
end

return HudController
