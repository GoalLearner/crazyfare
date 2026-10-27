--!strict
-- Keyboard, gamepad and touch. Exposes continuous axes and fires signals for one-shot actions.
-- Bindings live in Config.Keys. Phones (Config.Touch) drive forward by themselves, so one thumb is free for DRIFT and
-- BOOST: BRAKE slows to a stop, holds the car there for a moment (to pick up or drop off), then reverses. Steering is
-- an analog strip on the left; the ITEM button shows the item you hold.

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))
local State = require(script.Parent.Parent.State)

local InputController = {}

local onItem: Signal.Signal<nil> = Signal.new()
local onHonk: Signal.Signal<nil> = Signal.new()
local onReset: Signal.Signal<nil> = Signal.new()
local modeChanged: Signal.Signal<string> = Signal.new()
InputController.OnItem = onItem
InputController.OnHonk = onHonk
InputController.OnReset = onReset
InputController.ModeChanged = modeChanged -- "Keyboard" | "Gamepad" | "Touch", when the player switches

local keys = { forward = false, back = false, left = false, right = false, drift = false, boost = false }
local touch: { [string]: boolean } = { back = false, drift = false, boost = false }
local pad = { steer = 0, throttle = 0, brake = 0, drift = false, boost = false }
local DEADZONE = 0.18
local touchBuilt = false
local touchScreen: ScreenGui? = nil
local touchSteer = 0 -- -1..1 from the steering strip
local restSince: number? = nil -- touch: when a held BRAKE brought the car to a stop
local mode = "Keyboard"
local releaseChecks: { () -> () } = {} -- per frame: let go of any touch control whose finger has lifted

local function readMode(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif last == Enum.UserInputType.Keyboard or last.Name:sub(1, 5) == "Mouse" then
		return if touchBuilt and last ~= Enum.UserInputType.Keyboard then "Touch" else "Keyboard"
	end
	return if touchBuilt then "Touch" else "Keyboard"
end

-- What the player is driving with right now: "Keyboard", "Gamepad" or "Touch".
function InputController.GetMode(): string
	return mode
end

local function autoGas(): boolean
	return Config.Touch.AutoGas and touchBuilt and mode == "Touch"
end

-- Phones: forward unless BRAKE is held; a held BRAKE stops the car, holds it still for ReverseDelay, then reverses.
local function touchThrottle(): number
	if not touch.back then
		restSince = nil
		return 1
	end
	if math.abs(State.forwardSpeed) > Config.Touch.HoldSpeed then
		restSince = nil
		return -1 -- braking, or already reversing
	end
	local now = os.clock()
	local since = restSince or now
	restSince = since
	return if now - since >= Config.Touch.ReverseDelay then -1 else 0
end

function InputController.GetThrottle(): number
	local keyboard = (if keys.forward then 1 else 0) - (if keys.back then 1 else 0)
	if keyboard ~= 0 then
		return keyboard
	end
	if autoGas() then
		return touchThrottle()
	end
	return math.clamp(pad.throttle - pad.brake, -1, 1)
end

-- The brake is down (on a phone a held BRAKE at a standstill reads as throttle 0 while it holds the car; Dash still
-- counts it as braking).
function InputController.IsBraking(): boolean
	return InputController.GetThrottle() < 0 or (autoGas() and touch.back)
end

function InputController.GetSteer(): number
	local keyboard = (if keys.right then 1 else 0) - (if keys.left then 1 else 0)
	if keyboard ~= 0 then
		return keyboard
	end
	if touchSteer ~= 0 then
		return touchSteer
	end
	return pad.steer
end

function InputController.IsDrifting(): boolean
	return keys.drift or pad.drift or touch.drift
end

function InputController.IsBoosting(): boolean
	return keys.boost or pad.boost or touch.boost
end

-- The same press: a finger is its own InputObject; the mouse (Studio) reuses one per button.
local function samePress(input: InputObject, held: InputObject?): boolean
	if not held then
		return false
	end
	return input == held or (held.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function ended(input: InputObject): boolean
	return input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel
end

-- On-screen controls for phones and tablets: the steering strip on the left with ITEM and HONK above it, DRIFT in the
-- corner on the right with BRAKE beside it and BOOST above.
local function buildTouchControls()
	local UI = require(script.Parent.Parent.UI)
	local cfg = Config.Touch
	local screen = UI.Screen("CrazyFareTouch", 8, true) -- thumb-sized on every screen
	touchScreen = screen
	local size = cfg.ButtonSize
	local big = cfg.BigButton
	local m = cfg.Margin
	local gap = cfg.Gap
	local function button(label: string, x: number, y: number, anchorX: number, w: number, h: number): TextButton
		local b = UI.New("TextButton", {
			AnchorPoint = Vector2.new(anchorX, 1),
			Position = UDim2.new(anchorX, x, 1, -y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = Color3.fromRGB(30, 30, 40),
			BackgroundTransparency = cfg.Opacity,
			BorderSizePixel = 0,
			Font = UI.Font,
			TextSize = 16,
			TextColor3 = UI.White,
			Text = label,
			AutoButtonColor = false,
		}, screen) :: TextButton
		UI.Corner(math.floor(math.min(w, h) / 2), b)
		return b
	end
	-- Held until that finger lifts, even if it slides off the button first. A lift is caught three ways (over the
	-- button, anywhere, or the touch reading as ended on the next frame) because not every device reports all three.
	local function hold(b: TextButton, onDown: () -> (), onUp: () -> ())
		local held: InputObject? = nil
		local function release()
			if held then
				held = nil
				onUp()
				b.BackgroundTransparency = cfg.Opacity
			end
		end
		b.InputBegan:Connect(function(input: InputObject)
			if isPress(input) and not held then
				held = input
				onDown()
				b.BackgroundTransparency = cfg.Opacity * 0.4
			end
		end)
		b.InputEnded:Connect(function(input: InputObject)
			if isPress(input) and ended(input) then
				release()
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if samePress(input, held) then
				release()
			end
		end)
		table.insert(releaseChecks, function()
			local h = held
			if h and ended(h) then
				release()
			end
		end)
	end
	local function holdFlag(b: TextButton, field: string)
		hold(b, function()
			touch[field] = true
		end, function()
			touch[field] = false
		end)
	end
	local function tap(b: TextButton, signal: Signal.Signal<nil>)
		hold(b, function()
			signal:Fire()
		end, function() end)
	end

	-- Steering strip: how far from its middle your thumb sits is how hard you steer
	local strip = UI.New("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, m, 1, -m),
		Size = UDim2.fromOffset(cfg.SteerPad.X, cfg.SteerPad.Y),
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		BackgroundTransparency = cfg.Opacity,
		BorderSizePixel = 0,
	}, screen) :: Frame
	UI.Corner(math.floor(cfg.SteerPad.Y / 2), strip)
	UI.Label({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(24, 30), Text = "<", TextColor3 = UI.Muted }, strip)
	UI.Label({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(24, 30), Text = ">", TextColor3 = UI.Muted }, strip)
	local knob = UI.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(cfg.SteerKnob, cfg.SteerKnob),
		BackgroundColor3 = UI.White,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
	}, strip) :: Frame
	UI.Corner(math.floor(cfg.SteerKnob / 2), knob)
	local steerPress: InputObject? = nil
	local function steerTo(x: number)
		local half = math.max(1, (strip.AbsoluteSize.X - cfg.SteerKnob) / 2)
		local raw = math.clamp((x - (strip.AbsolutePosition.X + strip.AbsoluteSize.X / 2)) / half, -1, 1)
		local dz = cfg.SteerDeadzone
		touchSteer = if math.abs(raw) < dz then 0 else math.sign(raw) * (math.abs(raw) - dz) / (1 - dz)
		knob.Position = UDim2.new(0.5, raw * half, 0.5, 0)
	end
	strip.InputBegan:Connect(function(input: InputObject)
		if isPress(input) and not steerPress then
			steerPress = input
			steerTo(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local press = steerPress
		if not press then
			return
		end
		local mouseDrag = press.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
		if input == press or mouseDrag then
			steerTo(input.Position.X)
		end
	end)
	local function centre()
		steerPress = nil
		touchSteer = 0
		knob.Position = UDim2.fromScale(0.5, 0.5)
	end
	strip.InputEnded:Connect(function(input: InputObject)
		if steerPress and isPress(input) and ended(input) then
			centre()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if samePress(input, steerPress) then
			centre()
		end
	end)
	table.insert(releaseChecks, function()
		local press = steerPress
		if press and ended(press) then
			centre()
		end
	end)

	local above = m + cfg.SteerPad.Y + gap
	local item = button("ITEM", m, above, 0, cfg.ItemButton.X, cfg.ItemButton.Y)
	tap(item, onItem)
	tap(button("HONK", m + cfg.ItemButton.X + gap, above, 0, size, size), onHonk)
	holdFlag(button("DRIFT", -m, m, 1, big, big), "drift")
	holdFlag(button("BRAKE", -(m + big + gap), m, 1, size, size), "back")
	holdFlag(button("BOOST", -m, m + big + gap, 1, big, size), "boost")

	-- The ITEM button names the item you hold, in its color
	local shown: string? = nil
	State.SnapshotReceived:Connect(function()
		if State.item == shown then
			return
		end
		shown = State.item
		local def = Config.Items.Pool[State.item]
		item.Text = if def then string.upper(def.DisplayName) else "ITEM"
		item.TextColor3 = if def then def.Color else UI.Muted
		item.BackgroundTransparency = if def then cfg.Opacity * 0.6 else cfg.Opacity
	end)
end

local function handle(_actionName: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	local code = input.KeyCode
	local down = inputState == Enum.UserInputState.Begin
	local K = Config.Keys

	if code == K.PadSteer then
		local x = input.Position.X
		pad.steer = if math.abs(x) < DEADZONE then 0 else math.sign(x) * (math.abs(x) - DEADZONE) / (1 - DEADZONE)
		return Enum.ContextActionResult.Sink
	elseif code == K.PadThrottle then
		pad.throttle = input.Position.Z
		return Enum.ContextActionResult.Sink
	elseif code == K.PadBrake then
		pad.brake = input.Position.Z
		return Enum.ContextActionResult.Sink
	end

	if inputState ~= Enum.UserInputState.Begin and inputState ~= Enum.UserInputState.End then
		return Enum.ContextActionResult.Sink
	end

	if code == K.Throttle then
		keys.forward = down
	elseif code == K.Brake then
		keys.back = down
	elseif code == K.Left then
		keys.left = down
	elseif code == K.Right then
		keys.right = down
	elseif code == K.Drift then
		keys.drift = down
	elseif code == K.Boost then
		keys.boost = down
	elseif code == K.PadDrift then
		pad.drift = down
	elseif code == K.PadBoost then
		pad.boost = down
	elseif code == K.Item or code == K.PadItem then
		if down then
			onItem:Fire()
		end
	elseif code == K.Honk or code == K.PadHonk then
		if down then
			onHonk:Fire()
		end
	elseif code == K.Reset or code == K.PadReset then
		if down then
			onReset:Fire()
		end
	end
	return Enum.ContextActionResult.Sink
end

function InputController.Init()
	local K = Config.Keys
	ContextActionService:BindActionAtPriority(
		"CrazyFareDrive",
		handle,
		false,
		Enum.ContextActionPriority.High.Value,
		K.Throttle,
		K.Brake,
		K.Left,
		K.Right,
		K.Drift,
		K.Boost,
		K.Item,
		K.Honk,
		K.Reset,
		K.PadThrottle,
		K.PadBrake,
		K.PadSteer,
		K.PadDrift,
		K.PadBoost,
		K.PadItem,
		K.PadHonk,
		K.PadReset
	)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		touchBuilt = true
		buildTouchControls()
	end
	mode = readMode()
	UserInputService.LastInputTypeChanged:Connect(function()
		local now = readMode()
		if now ~= mode then
			mode = now
			local screen = touchScreen
			if screen then
				screen.Enabled = mode == "Touch" -- a gamepad on a phone hides the pads
			end
			modeChanged:Fire(mode)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		keys.forward = false
		keys.back = false
		keys.left = false
		keys.right = false
		keys.drift = false
		keys.boost = false
	end)
end

function InputController.Start()
	if #releaseChecks > 0 then
		RunService.Heartbeat:Connect(function()
			for _, check in releaseChecks do
				check()
			end
		end)
	end
end

return InputController
