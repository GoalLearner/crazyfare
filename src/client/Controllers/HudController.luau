--!strict
-- The HUD: rolling TOTAL + quota, round timer, fare card with a rolling FARE, stunt popups and combo, boost tank, item
-- slot, speed, center messages, coin burst + grade stamp on delivery, "TAKE ME TO ...!" over the cab, the destination
-- banner on arrival, the fare countdown by the cab, podium with gems and the rematch vote.
-- Reads State; the only thing it sends is RematchVote.

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
local RollingCounter = require(script.Parent.Parent.RollingCounter)
local SoundController = require(script.Parent.SoundController)

local HudController = {}

local screen: ScreenGui
local totalCounter: RollingCounter.Counter
local totalReady = false
local quotaBar: UI.Bar
local quotaLabel: TextLabel
local timerLabel: TextLabel
local phaseLabel: TextLabel
local arrow: TextLabel
local arrowDistance: TextLabel

local fareCard: Frame
local fareDest: TextLabel
local fareTier: TextLabel
local fareCounter: RollingCounter.Counter
local fareTimer: UI.Bar
local fareHp: UI.Bar
local fareHpLabel: TextLabel

local comboLabel: TextLabel
local comboBar: UI.Bar
local comboScale: UIScale
local boostBar: UI.Bar
local speedLabel: TextLabel
local itemSlot: Frame
local itemLabel: TextLabel

-- Where to: the passenger's shout over the cab, the arrival banner, the countdown by the cab
local shoutRoot: Frame
local shoutLabel: TextLabel
local shoutScale: UIScale
local shoutUntil = 0
local arrivalRoot: Frame
local arrivalLabel: TextLabel
local arrivalStroke: UIStroke
local arrivalShown = false
local arrivalToken = 0
local countdownLabel: TextLabel
local countdownScale: UIScale
local lastCountdown = -1
local COUNTDOWN_OFFSET = Vector2.new(84, 34) -- px from the point above the cab
local SHOUT_LIFT = 58 -- px above that point

local stampRoot: Frame
local stampLabel: TextLabel
local stampStroke: UIStroke
local stampScale: UIScale
local stampToken = 0
local lastTickAt = 0
local rng = Random.new()

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

-- A fare's color: its tier's, or gold for a Golden Fare.
local function fareColor(fare: State.FareInfo): Color3
	return if fare.golden then Config.Golden.Color else tierColor(fare.tier)
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

-- Stunt popups: they punch in just above the cab, climb and fade. The same stunt again soon tops up its own popup
-- (a long drift reads as one growing DRIFT! +$3.30), anything else stacks above.
type Popup = { root: Frame, label: TextLabel, scale: UIScale, kind: string, amount: number, born: number, stack: number }
local popupLayer: Frame
local popups: { Popup } = {}
local chain = 0 -- the stunt chain as the last Stunt event left it
local chainAt = 0 -- os.clock() of that event
local lostUntil = 0
local HOT = Color3.fromRGB(255, 150, 40)
local BLAZING = Color3.fromRGB(255, 70, 190)
local CASH_HEX = "#78F082"
local MAX_POPUPS = 5

local function punch(scale: UIScale, from: number)
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function popupText(kind: string, amount: number): string
	local name = Config.Stunts.Names[kind] or Config.SpeedFx.Labels[kind] or string.upper(kind)
	if amount > 0 then
		return string.format('%s <font color="%s">+%s</font>', name, CASH_HEX, UI.Money(amount))
	end
	return name
end

local function chainColor(n: number): Color3
	return if n >= Config.Stunts.BlazingChain then BLAZING elseif n >= Config.Stunts.HotChain then HOT else UI.Warn
end

local function addPopup(kind: string, amount: number)
	local now = os.clock()
	local last = popups[#popups]
	if last and last.kind == kind and now - last.born < Config.Stunts.PopupMergeSeconds then
		last.amount += amount
		last.label.Text = popupText(kind, last.amount)
		last.born = now
		punch(last.scale, 1.35)
		return
	end
	for _, popup in popups do
		popup.stack += 1
	end
	if #popups >= MAX_POPUPS then
		local oldest = table.remove(popups, 1)
		if oldest then
			oldest.root:Destroy()
		end
	end
	local root = UI.Frame({ AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(340, 40), BackgroundTransparency = 1 }, popupLayer)
	local label = UI.Label({ Size = UDim2.fromScale(1, 1), RichText = true, TextColor3 = chainColor(chain), TextStrokeTransparency = 0.2, Text = popupText(kind, amount) }, root)
	local scale = UI.New("UIScale", {}, root) :: UIScale
	punch(scale, 1.6)
	table.insert(popups, { root = root, label = label, scale = scale, kind = kind, amount = amount, born = now, stack = 0 })
end

-- Screen point just above the cab, or a spot above centre when the cab is off screen.
local function popupAnchor(): Vector2
	local camera = workspace.CurrentCamera
	local ch = State.chassis
	if camera and ch then
		local point, onScreen = camera:WorldToViewportPoint(ch.Position + Vector3.new(0, 7, 0))
		if onScreen then
			return Vector2.new(point.X, point.Y)
		end
	end
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return Vector2.new(size.X / 2, size.Y * 0.45)
end

local function updatePopups()
	local cfg = Config.Stunts
	local now = os.clock()
	local anchor = popupAnchor()
	for i = #popups, 1, -1 do
		local popup = popups[i]
		local t = (now - popup.born) / cfg.PopupSeconds
		if t >= 1 then
			popup.root:Destroy()
			table.remove(popups, i)
			continue
		end
		popup.root.Position = UDim2.fromOffset(anchor.X, anchor.Y - t * cfg.PopupRise - popup.stack * cfg.PopupStack)
		local fade = math.clamp((t - 0.6) / 0.4, 0, 1)
		popup.label.TextTransparency = fade
		popup.label.TextStrokeTransparency = 0.2 + 0.8 * fade
	end
end

-- Coins pop out of the cab and fly into the TOTAL, which waits for them before it rolls.
local function burstCoins(payout: number)
	local hud = Config.Hud
	local count = math.clamp(math.round(payout / 100 * hud.BurstCoinsPerDollar), hud.BurstCoinsMin, hud.BurstCoinsMax)
	local from = popupAnchor()
	local to = RollingCounter.GetCenter(totalCounter)
	for i = 1, count do
		local coin = UI.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(from.X, from.Y), Size = UDim2.fromOffset(30, 30), TextColor3 = UI.Cash, TextStrokeTransparency = 0.1, Text = "$" }, popupLayer)
		local angle = rng:NextNumber(0, math.pi * 2)
		local mid = from + Vector2.new(math.cos(angle), math.sin(angle)) * hud.BurstSpread * rng:NextNumber(0.45, 1)
		local out = TweenService:Create(coin, TweenInfo.new(hud.BurstOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(mid.X, mid.Y) })
		local fly = TweenService:Create(coin, TweenInfo.new(hud.BurstFlySeconds + i * 0.012, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(18, 18) })
		out.Completed:Once(function()
			fly:Play()
		end)
		fly.Completed:Once(function()
			coin:Destroy()
		end)
		out:Play()
	end
	RollingCounter.Hold(totalCounter, hud.CounterLandHold)
end

-- SPEEDY! / ON TIME / SLOW lands like a rubber stamp a beat after the payout, then fades.
local function showStamp(grade: string)
	local grades = Config.Grades
	local color = grades.Colors[grade] or UI.White
	stampToken += 1
	local token = stampToken
	task.delay(Config.Hud.StampDelay, function()
		if token ~= stampToken then
			return
		end
		stampLabel.Text = grades.Labels[grade] or string.upper(grade)
		stampLabel.TextColor3 = color
		stampLabel.TextTransparency = 0
		stampStroke.Color = color
		stampStroke.Transparency = 0
		stampRoot.Visible = true
		stampScale.Scale = 2.6
		stampRoot.Rotation = -18
		local slam = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(stampScale, slam, { Scale = 1 }):Play()
		TweenService:Create(stampRoot, slam, { Rotation = -8 }):Play()
		task.delay(Config.Hud.StampSeconds, function()
			if token ~= stampToken then
				return
			end
			local fade = TweenInfo.new(0.3)
			TweenService:Create(stampLabel, fade, { TextTransparency = 1 }):Play()
			local tween = TweenService:Create(stampStroke, fade, { Transparency = 1 })
			tween.Completed:Once(function()
				if token == stampToken then
					stampRoot.Visible = false
				end
			end)
			tween:Play()
		end)
	end)
end

-- "TAKE ME TO THE STADIUM!" in a speech bubble over the cab.
local function showShout(text: string)
	shoutLabel.Text = text
	shoutRoot.Visible = true
	shoutUntil = os.clock() + Config.Hud.ShoutSeconds
	punch(shoutScale, 1.4)
end

-- The destination's name slides in from the left, holds, and slides out to the right.
local function showArrival(name: string, color: Color3)
	arrivalToken += 1
	local token = arrivalToken
	arrivalLabel.Text = name
	arrivalLabel.TextColor3 = color
	arrivalStroke.Color = color
	arrivalRoot.Position = UDim2.fromScale(-0.5, 0.18)
	arrivalRoot.Visible = true
	TweenService:Create(arrivalRoot, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.18) }):Play()
	task.delay(Config.Hud.ArrivalSeconds, function()
		if token ~= arrivalToken then
			return
		end
		local out = TweenService:Create(arrivalRoot, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(1.5, 0.18) })
		out.Completed:Once(function()
			if token == arrivalToken then
				arrivalRoot.Visible = false
			end
		end)
		out:Play()
	end)
end

-- Seconds left on the fare, beside the cab: yellow, then red with a tick and a punch every second.
local function updateCountdown(fare: State.FareInfo?, playing: boolean, now: number)
	if not fare or not playing then
		countdownLabel.Visible = false
		lastCountdown = -1
		return
	end
	local hud = Config.Hud
	local left = math.max(0, math.ceil(fare.deadline - now))
	local anchor = popupAnchor()
	countdownLabel.Position = UDim2.fromOffset(anchor.X + COUNTDOWN_OFFSET.X, anchor.Y + COUNTDOWN_OFFSET.Y)
	countdownLabel.Text = tostring(left)
	countdownLabel.TextColor3 = if left <= hud.CountdownDanger then UI.Danger elseif left <= hud.CountdownWarn then UI.Warn else UI.White
	countdownLabel.Visible = true
	if left ~= lastCountdown then
		if lastCountdown >= 0 and left <= hud.CountdownDanger then
			punch(countdownScale, 1.5)
			SoundController.PlayOneShot("Tick", 0.8)
		end
		lastCountdown = left
	end
end

-- Steps a counter; a tick sound per dime boundary, capped per second across both counters.
local function stepCounter(counter: RollingCounter.Counter, dt: number, pitch: number)
	local ticked = RollingCounter.Step(counter, dt)
	local now = os.clock()
	if ticked and now - lastTickAt >= 1 / Config.Hud.CounterTickMaxPerSecond then
		lastTickAt = now
		SoundController.PlayOneShot("Tick", pitch)
	end
end

local function build()
	screen = UI.Screen("CrazyFareHud", 10)

	-- Cash + quota (top-left)
	local cashBox = UI.Frame({ Position = UDim2.fromOffset(24, 76), Size = UDim2.fromOffset(220, 92), BackgroundTransparency = 1 }, screen)
	totalCounter = RollingCounter.new(cashBox, Config.Hud.TotalHeight, UI.Cash, UDim2.fromOffset(0, 4), 0)
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
	fareCard = UI.Frame({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Size = UDim2.fromOffset(240, 142), Visible = false }, screen)
	UI.Corner(10, fareCard)
	fareDest = UI.Label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, fareCard)
	fareTier = UI.Label({ Position = UDim2.fromOffset(12, 36), Size = UDim2.fromOffset(110, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "SHORT" }, fareCard)
	fareCounter = RollingCounter.new(fareCard, Config.Hud.FareHeight, UI.Cash, UDim2.new(1, -12, 0, 32), 1)
	fareTimer = UI.Bar({ Position = UDim2.fromOffset(12, 70), Size = UDim2.new(1, -24, 0, 12) }, UI.Warn, fareCard)
	fareHp = UI.Bar({ Position = UDim2.fromOffset(12, 98), Size = UDim2.new(1, -24, 0, 14) }, UI.Danger, fareCard)
	fareHpLabel = UI.Label({ Position = UDim2.fromOffset(12, 116), Size = UDim2.new(1, -24, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Muted, Font = UI.FontMedium, Text = "PASSENGER" }, fareCard)

	-- Combo + boost + speed (bottom-center)
	local center = UI.Frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(260, 90), BackgroundTransparency = 1 }, screen)
	comboLabel = UI.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(200, 40), TextColor3 = UI.Warn, Text = "" }, center)
	comboScale = UI.New("UIScale", {}, comboLabel) :: UIScale
	comboBar = UI.Bar({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(200, 8) }, UI.Warn, center)
	popupLayer = UI.Frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, screen)

	-- Delivery grade stamp: an inked box slammed on screen under the payout
	stampRoot = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(330, 84), BackgroundTransparency = 1, Rotation = -8, Visible = false }, screen)
	UI.Corner(12, stampRoot)
	stampStroke = UI.Stroke(UI.White, 5, stampRoot)
	stampStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stampScale = UI.New("UIScale", {}, stampRoot) :: UIScale
	stampLabel = UI.Label({ Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 1, -12), TextStrokeTransparency = 0.2 }, stampRoot)

	-- The passenger's shout: a speech bubble that rides above the cab
	shoutRoot = UI.Frame({ AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(400, 46), BackgroundColor3 = UI.White, BackgroundTransparency = 0.04, Visible = false }, screen)
	UI.Corner(14, shoutRoot)
	shoutScale = UI.New("UIScale", {}, shoutRoot) :: UIScale
	shoutLabel = UI.Label({ Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -24, 1, -10), TextColor3 = UI.Black, TextStrokeTransparency = 1 }, shoutRoot)

	-- Arrival banner: the destination's name slides across as you pull up
	arrivalRoot = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.5, 0.18), Size = UDim2.fromOffset(520, 62), BackgroundColor3 = UI.Black, BackgroundTransparency = 0.12, Visible = false }, screen)
	UI.Corner(12, arrivalRoot)
	arrivalStroke = UI.Stroke(UI.White, 4, arrivalRoot)
	arrivalStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	arrivalLabel = UI.Label({ Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -32, 1, -12) }, arrivalRoot)

	-- The fare countdown, big, beside the cab
	countdownLabel = UI.Label({ AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(70, 56), TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 0.1, Visible = false }, screen)
	countdownScale = UI.New("UIScale", {}, countdownLabel) :: UIScale
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
		UI.Label({ Position = UDim2.fromOffset(48, 4), Size = UDim2.fromOffset(110, 28), Text = if entry.bot then "BOT " .. entry.name else entry.name, TextColor3 = if entry.bot then UI.Muted else UI.White, TextXAlignment = Enum.TextXAlignment.Left }, row)
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
		local stunts = payload.stunts or 0
		local parts = {}
		if tip > 0 then
			table.insert(parts, "TIP " .. UI.Money(tip))
		end
		if stunts > 0 then
			table.insert(parts, "STUNTS " .. UI.Money(stunts))
		end
		if payload.line then
			table.insert(parts, payload.line)
		end
		if payload.bonus then
			table.insert(parts, payload.bonus)
		end
		showMessage("+" .. UI.Money(payload.payout or 0), UI.Cash, Config.Hud.PayoutPunchSeconds, if #parts > 0 then table.concat(parts, "  ·  ") else nil)
		burstCoins(payload.payout or 0)
		if payload.grade then
			showStamp(payload.grade)
		end
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
		showMessage(string.format("-%d HP", payload.amount or 0), UI.Danger, Config.Hud.CrashMessageSeconds) -- the rider yells the line
	elseif payload.kind == "Golden" then
		local g = Config.Golden
		showMessage(g.Announce, g.Color, g.AnnounceSeconds, g.AnnounceSub)
	elseif payload.kind == "Stunt" then
		local before = chain
		chain = payload.chain or chain
		chainAt = os.clock()
		lostUntil = 0
		if chain > before and chain >= 2 then
			punch(comboScale, 1.4)
		end
		addPopup(payload.stunt or "", payload.amount or 0)
	elseif payload.kind == "ChainBroken" then
		chain = 0
		if payload.reason ~= "idle" then
			lostUntil = os.clock() + Config.Stunts.LostSeconds
			punch(comboScale, 1.3)
		end
	elseif payload.kind == "Claimed" then
		RollingCounter.Snap(fareCounter, 0) -- the meter starts: it rolls up to the base fare
		arrivalShown = false
		local name = payload.destinationName or ""
		if name ~= "" then
			showShout("TAKE ME TO " .. name .. "!")
		else
			local def = Config.Fares.Tiers[payload.tier or ""]
			showMessage((if def then def.Label else "FARE") .. " TRIP", tierColor(payload.tier or ""), 1.0, "Drop them at the beacon")
		end
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

local function update(dt: number)
	local now = workspace:GetServerTimeNow()
	local round = State.round
	local phase = State.GetPhase()

	if not totalReady then
		RollingCounter.Snap(totalCounter, State.cash)
		totalReady = true
	end
	RollingCounter.SetTarget(totalCounter, State.cash)
	stepCounter(totalCounter, dt, 1)
	local quota = if round then round.quota else Money.Cents(Config.Round.Quotas[1])
	UI.SetBar(quotaBar, if quota > 0 then RollingCounter.GetValue(totalCounter) / quota else 0)
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
		fareDest.Text = if fare.destinationName ~= "" then fare.destinationName else "DROP-OFF"
		fareDest.TextColor3 = fareColor(fare)
		local tierLabel = (Config.Fares.Tiers[fare.tier] or Config.Fares.Tiers.Green).Label
		fareTier.Text = if fare.golden then Config.Golden.Label .. " " .. tierLabel else tierLabel
		fareTier.TextColor3 = if fare.golden then Config.Golden.Color else UI.Muted
		RollingCounter.SetTarget(fareCounter, fare.base + fare.stunts)
		stepCounter(fareCounter, dt, 1.25)
		local total = math.max(0.01, fare.deadline - fare.startedAt)
		local remaining = VecUtil.Clamp01((fare.deadline - now) / total)
		UI.SetBar(fareTimer, remaining, if remaining < 0.25 then UI.Danger else UI.Warn)
		local hpFrac = if State.maxHp > 0 then State.hp / State.maxHp else 1
		UI.SetBar(fareHp, hpFrac, if hpFrac > 0.5 then UI.Cash else (if hpFrac > 0.25 then UI.Warn else UI.Danger))
		local kindDef = Config.PassengerTypes.Kinds[fare.passenger] or Config.PassengerTypes.Kinds.Regular
		fareHpLabel.Text = string.format("%s %d/%d", kindDef.Label, math.round(State.hp), State.maxHp)

		-- Destination arrow relative to the camera heading
		local ch = State.chassis
		local camera = workspace.CurrentCamera
		if ch and camera then
			local toDest = VecUtil.Flat(fare.destination - ch.Position)
			local dist = toDest.Magnitude
			if not arrivalShown and fare.destinationName ~= "" and dist <= Config.Hud.ArrivalDistance then
				arrivalShown = true
				showArrival(fare.destinationName, fareColor(fare))
			end
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

	-- Stunt chain: the counter, a bar for the time left before it ends, and COMBO LOST when a crash or bail breaks it.
	-- The snapshot's chain catches resets that send no event (a new round).
	local clock = os.clock()
	local since = clock - chainAt
	if chain > 0 and (since >= Config.Stunts.ChainIdleSeconds or (State.combo == 0 and since > 0.6)) then
		chain = 0
	end
	if clock < lostUntil then
		comboLabel.Text = "COMBO LOST"
		comboLabel.TextColor3 = UI.Danger
		comboBar.back.Visible = false
	elseif chain >= 2 then
		comboLabel.Text = "COMBO x" .. chain
		comboLabel.TextColor3 = chainColor(chain)
		UI.SetBar(comboBar, 1 - since / Config.Stunts.ChainIdleSeconds, chainColor(chain))
		comboBar.back.Visible = true
	else
		comboLabel.Text = ""
		comboBar.back.Visible = false
	end
	updatePopups()

	-- Where to: the shout rides above the cab while it lasts; the countdown sits beside it
	local clockNow = os.clock()
	if shoutRoot.Visible then
		if clockNow >= shoutUntil then
			shoutRoot.Visible = false
		else
			local anchor = popupAnchor()
			shoutRoot.Position = UDim2.fromOffset(anchor.X, anchor.Y - SHOUT_LIFT)
		end
	end
	updateCountdown(State.fare, phase == "Playing", now)

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
	State.Dashed:Connect(function()
		addPopup("Dash", 0) -- "DASH!" over the cab, no cash: a trick, not a paid stunt
	end)
end

function HudController.Start()
	RunService.RenderStepped:Connect(update)
end

return HudController
