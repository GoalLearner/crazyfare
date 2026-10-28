--!strict
-- OPTIONS (Config.Options): music and sound volume in steps, camera shake and speed effects on or off. Opens from the
-- title screen and from the side stack (under COLLECTION) whenever you're not mid-round at the wheel. A change applies
-- at once (State.SettingsChanged: SoundController, CameraController, SpeedFxController) and is saved to your profile
-- a moment after the last tap (SaveSettings).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local OptionsController = {}

local ON_COLOR = Color3.fromRGB(60, 170, 90)
local OFF_COLOR = Color3.fromRGB(70, 70, 82)
local PIP_OFF = Color3.fromRGB(50, 50, 60)

local openButton: TextButton
local panel: Frame
local isOpen = false
local saveToken = 0
local redraws: { () -> () } = {}

local function redraw()
	for _, fn in redraws do
		fn()
	end
end

-- Apply now, save shortly (one save for a run of taps).
local function change(edit: (Types.SettingsPayload) -> ())
	local s = State.settings
	local copy: Types.SettingsPayload = { music = s.music, sfx = s.sfx, shake = s.shake, speedFx = s.speedFx }
	edit(copy)
	State.settings = copy
	State.SettingsChanged:Fire()
	redraw()
	saveToken += 1
	local token = saveToken
	task.delay(Config.Options.SaveDelay, function()
		if token == saveToken then
			Remotes.Get("SaveSettings"):FireServer(State.settings)
		end
	end)
end

local function smallButton(text: string, position: UDim2, parent: Instance): TextButton
	local b = UI.New("TextButton", {
		Position = position,
		Size = UDim2.fromOffset(40, 36),
		BackgroundColor3 = OFF_COLOR,
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 22,
		TextColor3 = UI.White,
		Text = text,
	}, parent) :: TextButton
	UI.Corner(8, b)
	return b
end

local function row(label: string, y: number): Frame
	local r = UI.Frame({ Position = UDim2.fromOffset(24, y), Size = UDim2.new(1, -48, 0, 40), BackgroundTransparency = 1 }, panel)
	UI.Label({ Size = UDim2.new(0.45, 0, 1, 0), Text = label, Font = UI.FontMedium, TextScaled = false, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left }, r)
	return r
end

-- A volume: [-] a pip per step above silent [+] (all dark = off).
local function volumeRow(label: string, y: number, get: () -> number, set: (Types.SettingsPayload, number) -> ())
	local r = row(label, y)
	local steps = #Config.Options.VolumeSteps
	local n = steps - 1
	local minus = smallButton("-", UDim2.new(1, -(40 * 2 + 8 * 2 + 20 * n + 4 * (n - 1)), 0, 2), r)
	local pips: { Frame } = {}
	for i = 1, n do
		local pip = UI.Frame({ Position = UDim2.new(1, -(40 + 8 + 20 * (n - i + 1) + 4 * (n - i)), 0, 8), Size = UDim2.fromOffset(20, 24), BackgroundTransparency = 0 }, r)
		UI.Corner(4, pip)
		pips[i] = pip
	end
	local plus = smallButton("+", UDim2.new(1, -40, 0, 2), r)
	minus.Activated:Connect(function()
		change(function(s)
			set(s, math.max(1, get() - 1))
		end)
	end)
	plus.Activated:Connect(function()
		change(function(s)
			set(s, math.min(steps, get() + 1))
		end)
	end)
	table.insert(redraws, function()
		local level = get()
		for i, pip in pips do
			pip.BackgroundColor3 = if i + 1 <= level then UI.Warn else PIP_OFF
		end
	end)
end

local function switchRow(label: string, y: number, get: () -> boolean, set: (Types.SettingsPayload, boolean) -> ())
	local r = row(label, y)
	local b = smallButton("", UDim2.new(1, -96, 0, 2), r)
	b.Size = UDim2.fromOffset(96, 36)
	b.TextSize = 18
	b.Activated:Connect(function()
		change(function(s)
			set(s, not get())
		end)
	end)
	table.insert(redraws, function()
		local on = get()
		b.Text = if on then Config.Options.On else Config.Options.Off
		b.BackgroundColor3 = if on then ON_COLOR else OFF_COLOR
	end)
end

function OptionsController.Open()
	isOpen = true
	panel.Visible = true
	redraw()
end

function OptionsController.Close()
	isOpen = false
	panel.Visible = false
end

function OptionsController.IsOpen(): boolean
	return isOpen
end

-- The side button: parked (between rounds, or not driving), never on the title screen (it has its own), and not on a
-- phone, where the bottom of the stack would sit on the driving pads (phones use the title screen's OPTIONS).
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local function onRound(payload: Types.RoundStatePayload)
	local parked = (payload.phase ~= "Playing" and payload.phase ~= "Countdown") or (State.sessionState ~= "Driver" and State.sessionState ~= "")
	openButton.Visible = parked and State.sessionState ~= "Title" and not touchOnly
	if not parked and isOpen then
		OptionsController.Close()
	end
end

local function build()
	local labels = Config.Options.Labels
	local screen = UI.Screen("CrazyFareOptions", 45)
	screen:SetAttribute(Config.Title.KeepAttribute, true) -- the title screen's OPTIONS opens it
	openButton = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24 + Config.Hud.MinimapSize + 10 + (34 + 8) * 6),
		Size = UDim2.fromOffset(Config.Hud.MinimapSize, 34),
		BackgroundColor3 = Color3.fromRGB(60, 60, 74),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = Config.Options.Button,
		Visible = false,
	}, screen) :: TextButton
	UI.Corner(8, openButton)
	openButton.Activated:Connect(function()
		if isOpen then
			OptionsController.Close()
		else
			OptionsController.Open()
		end
	end)

	panel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 280), BackgroundTransparency = 0.05, Visible = false }, screen)
	UI.CenterBelowTopbar(panel)
	UI.Corner(16, panel)
	UI.Label({ Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(240, 36), Text = Config.Options.Title, TextXAlignment = Enum.TextXAlignment.Left }, panel)
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
	close.Activated:Connect(OptionsController.Close)

	volumeRow(labels.Music, 70, function()
		return State.settings.music
	end, function(s, v)
		s.music = v
	end)
	volumeRow(labels.Sfx, 118, function()
		return State.settings.sfx
	end, function(s, v)
		s.sfx = v
	end)
	switchRow(labels.Shake, 166, function()
		return State.settings.shake
	end, function(s, v)
		s.shake = v
	end)
	switchRow(labels.SpeedFx, 214, function()
		return State.settings.speedFx
	end, function(s, v)
		s.speedFx = v
	end)
end

function OptionsController.Init()
	build()
	State.RoundChanged:Connect(onRound)
	State.SessionChanged:Connect(function()
		local round = State.round
		if round then
			onRound(round)
		end
	end)
	State.SettingsChanged:Connect(function()
		if isOpen then
			redraw()
		end
	end)
end

function OptionsController.Start() end

return OptionsController
