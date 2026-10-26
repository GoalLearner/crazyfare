--!strict
-- Keyboard + basic gamepad. Exposes continuous axes and fires signals for one-shot actions.
-- Bindings live in Config.Keys.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared:WaitForChild("Signal"))

local InputController = {}

local onItem: Signal.Signal<nil> = Signal.new()
local onHonk: Signal.Signal<nil> = Signal.new()
local onReset: Signal.Signal<nil> = Signal.new()
InputController.OnItem = onItem
InputController.OnHonk = onHonk
InputController.OnReset = onReset

local keys = { forward = false, back = false, left = false, right = false, drift = false, boost = false }
local pad = { steer = 0, throttle = 0, brake = 0, drift = false, boost = false }
local DEADZONE = 0.18

function InputController.GetThrottle(): number
	local keyboard = (if keys.forward then 1 else 0) - (if keys.back then 1 else 0)
	if keyboard ~= 0 then
		return keyboard
	end
	return math.clamp(pad.throttle - pad.brake, -1, 1)
end

function InputController.GetSteer(): number
	local keyboard = (if keys.right then 1 else 0) - (if keys.left then 1 else 0)
	if keyboard ~= 0 then
		return keyboard
	end
	return pad.steer
end

function InputController.IsDrifting(): boolean
	return keys.drift or pad.drift
end

function InputController.IsBoosting(): boolean
	return keys.boost or pad.boost
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
	UserInputService.WindowFocusReleased:Connect(function()
		keys.forward = false
		keys.back = false
		keys.left = false
		keys.right = false
		keys.drift = false
		keys.boost = false
	end)
end

function InputController.Start() end

return InputController
