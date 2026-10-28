--!strict
-- The title screen (Config.Title): every join opens here, over a drone shot of the live map (CameraController). The
-- CRAZYFARE logo bobs, a splash line pulses, and four buttons: PLAY (the server places you: MatchController), GARAGE,
-- OPTIONS and CREDITS. A line under them says what the server is doing right now. While you're on it every other
-- CrazyFare screen is hidden except the panels its buttons open, and a warm grade tints the view; leaving it fades
-- the menu and the grade out and gives the other screens back.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)
local GarageController = require(script.Parent.GarageController)
local OptionsController = require(script.Parent.OptionsController)
local CreditsController = require(script.Parent.CreditsController)

local TitleController = {}

local cfg = Config.Title
local playerGui: PlayerGui
local back: ScreenGui -- full-screen pieces (the shade behind the buttons), never scaled
local front: ScreenGui -- logo, splash, buttons (scaled for phones)
local backGroup: CanvasGroup
local frontGroup: CanvasGroup
local logo: Frame
local logoY = 0
local splash: TextLabel
local splashScale: UIScale
local playButton: TextButton
local liveLabel: TextLabel
local grade: ColorCorrectionEffect? = nil
local hidden: { [ScreenGui]: boolean } = {} -- screens turned off for the title, and whether each was on
local onTitle = false
local pressedAt = -math.huge

local function isOurs(gui: ScreenGui): boolean
	return gui ~= back and gui ~= front and string.sub(gui.Name, 1, 9) == "CrazyFare" and gui:GetAttribute(cfg.KeepAttribute) ~= true
end

-- Every other CrazyFare screen off (again each frame: some switch themselves back on as state arrives).
local function hideOthers()
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") and isOurs(child) and child.Enabled then
			if hidden[child] == nil then
				hidden[child] = true
			end
			child.Enabled = false
		end
	end
end

-- Back on, except the ones that decide for themselves (they already redrew for the new state).
local function restoreOthers()
	for gui, wasOn in hidden do
		if wasOn and gui.Parent and gui:GetAttribute(cfg.SelfManagedAttribute) ~= true then
			gui.Enabled = true
		end
	end
	table.clear(hidden)
end

local function setGrade(on: boolean)
	local g = cfg.Grade
	if on then
		local existing = grade
		if existing then
			existing:Destroy()
		end
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "TitleGrade"
		effect.TintColor = g.Tint
		effect.Saturation = g.Saturation
		effect.Contrast = g.Contrast
		effect.Brightness = g.Brightness
		effect.Parent = Lighting
		grade = effect
		return
	end
	local effect = grade
	if not effect then
		return
	end
	grade = nil
	local tween = TweenService:Create(effect, TweenInfo.new(g.FadeSeconds), { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 })
	tween.Completed:Once(function()
		effect:Destroy()
	end)
	tween:Play()
end

local function show()
	onTitle = true
	pressedAt = -math.huge
	local lines = cfg.Splash.Lines
	splash.Text = lines[math.random(1, #lines)] -- (an unseeded Random gave every Studio test client the same line)
	back.Enabled = true
	front.Enabled = true
	backGroup.GroupTransparency = 0
	frontGroup.GroupTransparency = 0
	playButton.Active = true
	setGrade(true)
	hideOthers()
end

local function hide()
	onTitle = false
	GarageController.Close()
	OptionsController.Close()
	CreditsController.Close()
	restoreOthers()
	setGrade(false)
	local info = TweenInfo.new(cfg.FadeSeconds)
	TweenService:Create(backGroup, info, { GroupTransparency = 1 }):Play()
	local tween = TweenService:Create(frontGroup, info, { GroupTransparency = 1 })
	tween.Completed:Once(function()
		if not onTitle then
			back.Enabled = false
			front.Enabled = false
		end
	end)
	tween:Play()
end

-- What the server is doing, under the buttons: a round on, the Pit Stop, or the next match's countdown.
local function liveText(): string
	local round = State.round
	if not round then
		return ""
	end
	local snap = State.snapshot
	local driving = if snap then #snap.players else 0
	local phase = round.phase
	if phase == "Waiting" or phase == "MatchEnd" then
		local left = round.endsAt - workspace:GetServerTimeNow()
		if round.endsAt > 0 and left > 0 then
			local s = math.ceil(left)
			return string.format(cfg.LiveCountdown, s // 60, s % 60)
		end
		return cfg.LiveWaiting
	elseif phase == "PitStop" then
		return string.format(cfg.LivePitStop, driving)
	end
	return string.format(cfg.LiveRound, round.round, driving)
end

local function play()
	if not onTitle or os.clock() - pressedAt < cfg.PlayRetrySeconds then
		return
	end
	pressedAt = os.clock() -- the answer is your new state; press again only if it never comes
	Remotes.Get("Play"):FireServer()
end

local function menuButton(text: string, color: Color3, textColor: Color3, size: UDim2, position: UDim2, textSize: number, parent: Instance): TextButton
	local b = UI.New("TextButton", {
		Position = position,
		Size = size,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UI.Font,
		TextSize = textSize,
		TextColor3 = textColor,
		Text = text,
	}, parent) :: TextButton
	UI.Corner(10, b)
	local stroke = UI.Stroke(cfg.Logo.Outline, 2, b)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return b
end

local function build()
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local L = cfg.Logo

	back = UI.Screen("CrazyFareTitleBack", 40, true, false)
	back.Enabled = false
	backGroup = UI.New("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, back) :: CanvasGroup
	-- a shade rising from the bottom so the buttons read over a bright city
	local shade = UI.Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.Black, BackgroundTransparency = 0 }, backGroup)
	UI.New("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.35, 1),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
	}, shade)

	front = UI.Screen("CrazyFareTitle", 41)
	front.Enabled = false
	frontGroup = UI.New("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, front) :: CanvasGroup

	-- the logo: chunky letters, a gold gradient, a dark outline, a taxi checker stripe under it
	local stripeHeight = L.CheckSize * 2
	logo = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(L.Width, L.Size + stripeHeight + 10), BackgroundTransparency = 1, Rotation = L.Tilt }, frontGroup)
	UI.OnFit(function()
		logoY = UI.BelowTopbar(Config.Hud.TopbarHeight + L.TopGap) -- clear of Roblox's buttons, which reach under a wide logo on phones
	end)
	local word = UI.Label({ Size = UDim2.new(1, 0, 0, L.Size), Text = L.Text, Font = L.Font, TextColor3 = UI.White, TextStrokeTransparency = 1 }, logo)
	UI.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(L.Top, L.Bottom) }, word)
	local outline = UI.Stroke(L.Outline, L.OutlineThickness, word)
	outline.LineJoinMode = Enum.LineJoinMode.Round
	local stripe = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, L.Size + 6), Size = UDim2.fromOffset(L.Checks * L.CheckSize, stripeHeight), BackgroundColor3 = L.Outline, BackgroundTransparency = 0 }, logo)
	UI.Stroke(L.Outline, 3, stripe)
	for column = 0, L.Checks - 1 do
		for row = 0, 1 do
			if (column + row) % 2 == 0 then
				UI.Frame({ Position = UDim2.fromOffset(column * L.CheckSize, row * L.CheckSize), Size = UDim2.fromOffset(L.CheckSize, L.CheckSize), BackgroundColor3 = L.Top, BackgroundTransparency = 0 }, stripe)
			end
		end
	end

	-- the splash line, tilted off the logo's corner
	local S = cfg.Splash
	splash = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -40, 0, L.Size + 2),
		Size = UDim2.fromOffset(340, S.Size + 6),
		Rotation = S.Tilt - L.Tilt,
		Font = L.Font,
		TextColor3 = S.Color,
		TextStrokeTransparency = 1,
		ZIndex = 3,
	}, logo)
	UI.Stroke(S.Outline, 2, splash)
	splashScale = UI.New("UIScale", {}, splash) :: UIScale

	-- the buttons, low in the middle, the city showing between them and the logo
	local w = cfg.ButtonWidth
	local gap = cfg.ButtonGap
	local h = cfg.ButtonHeight
	local column = UI.Frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -36), Size = UDim2.fromOffset(w, cfg.PlayHeight + (h + gap) * 2 + gap + 22), BackgroundTransparency = 1 }, frontGroup)
	playButton = menuButton(cfg.Buttons.Play, cfg.PlayColor, UI.Black, UDim2.fromOffset(w, cfg.PlayHeight), UDim2.fromOffset(0, 0), 30, column)
	playButton.Activated:Connect(play)
	local y = cfg.PlayHeight + gap
	local garage = menuButton(cfg.Buttons.Garage, cfg.ButtonColor, UI.White, UDim2.fromOffset(w, h), UDim2.fromOffset(0, y), 20, column)
	garage.Activated:Connect(function()
		GarageController.Open()
	end)
	y += h + gap
	local half = (w - gap) / 2
	local options = menuButton(cfg.Buttons.Options, cfg.ButtonColor, UI.White, UDim2.fromOffset(half, h), UDim2.fromOffset(0, y), 18, column)
	options.Activated:Connect(function()
		OptionsController.Open()
	end)
	local credits = menuButton(cfg.Buttons.Credits, cfg.ButtonColor, UI.White, UDim2.fromOffset(half, h), UDim2.fromOffset(half + gap, y), 18, column)
	credits.Activated:Connect(function()
		CreditsController.Open()
	end)
	y += h + gap
	liveLabel = UI.Label({ Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(w, 20), Text = "", Font = UI.FontMedium, TextColor3 = UI.White, TextStrokeTransparency = 0.3 }, column)
end

local function update()
	if not onTitle then
		return
	end
	hideOthers()
	local t = os.clock()
	local L = cfg.Logo
	logo.Position = UDim2.new(0.5, 0, 0, logoY + math.sin(t / L.BobSeconds * math.pi * 2) * L.BobPixels)
	local S = cfg.Splash
	splashScale.Scale = 1 + S.Pulse * math.abs(math.sin(t / S.PulseSeconds * math.pi))
	liveLabel.Text = liveText()
	-- a panel opened from the menu takes the screen; the drone keeps flying behind it
	local panelOpen = GarageController.IsOpen() or OptionsController.IsOpen() or CreditsController.IsOpen()
	frontGroup.Visible = not panelOpen
	backGroup.Visible = not panelOpen
end

function TitleController.Init()
	build()
	State.SessionChanged:Connect(function(state: string)
		if state == "Title" and not onTitle then
			show()
		elseif state ~= "Title" and onTitle then
			hide()
		end
	end)
	if State.sessionState == "Title" then
		show()
	end
	-- a screen made while the title is up starts hidden
	playerGui.ChildAdded:Connect(function(child: Instance)
		if onTitle and child:IsA("ScreenGui") then
			hideOthers()
		end
	end)
end

function TitleController.Start()
	RunService.RenderStepped:Connect(update)
end

return TitleController
