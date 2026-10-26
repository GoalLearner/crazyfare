--!strict
-- Chase camera: sits behind and above the taxi, follows its heading smoothly, widens FOV with speed.
-- Holds its heading during a spinout so the player sees the spin instead of becoming it.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local VecUtil = require(Shared:WaitForChild("VecUtil"))
local State = require(script.Parent.Parent.State)

local CameraController = {}

local camera = workspace.CurrentCamera
local camPos: Vector3? = nil
local heldLook = Vector3.new(0, 0, -1)
local fov = Config.Camera.FovBase
local shakeAmount = 0
local shakeRng = Random.new()

local function overview(dt: number)
	local half = Config.Map.City.Blockout.Half
	local target = Vector3.new(0, 0, 0)
	local desired = Vector3.new(0, half * 1.1, half * 0.9)
	camPos = if camPos then camPos:Lerp(desired, VecUtil.ExpAlpha(2, dt)) else desired
	camera.CFrame = CFrame.lookAt(camPos :: Vector3, target)
	fov = fov + (Config.Camera.FovBase - fov) * VecUtil.ExpAlpha(4, dt)
	camera.FieldOfView = fov
end

local function follow(dt: number)
	local ch = State.chassis
	if not ch or not ch:IsDescendantOf(workspace) then
		overview(dt)
		return
	end
	local cfg = Config.Camera
	local now = workspace:GetServerTimeNow()
	local spinning = now < State.spinUntil
	local look = if spinning then heldLook else VecUtil.FlatUnit(ch.CFrame.LookVector, heldLook)
	heldLook = look

	local target = ch.Position
	local desired = target - look * cfg.Distance + Vector3.new(0, cfg.Height, 0)
	camPos = if camPos then (camPos :: Vector3):Lerp(desired, VecUtil.ExpAlpha(cfg.Stiffness, dt)) else desired
	local aim = target + look * cfg.LookAhead + Vector3.new(0, 2, 0)
	local shakeOffset = Vector3.zero
	if shakeAmount > 0.01 then
		shakeOffset = Vector3.new(shakeRng:NextNumber(-1, 1), shakeRng:NextNumber(-1, 1), 0) * shakeAmount
		shakeAmount *= math.max(0, 1 - Config.Shake.Decay * dt)
	end
	camera.CFrame = CFrame.lookAt(camPos :: Vector3, aim) * CFrame.new(shakeOffset)

	local speedFrac = math.clamp(State.speed / State.stats.TopSpeed, 0, 1)
	local targetFov = cfg.FovBase + cfg.FovSpeedBonus * speedFrac + (if State.boosting then cfg.FovBoostBonus else 0)
	fov = fov + (targetFov - fov) * VecUtil.ExpAlpha(5, dt)
	camera.FieldOfView = fov
end

function CameraController.Init()
	camera = workspace.CurrentCamera
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		camera = workspace.CurrentCamera
	end)
	State.VehicleChanged:Connect(function()
		camPos = nil
	end)
	State.Shake:Connect(function(strength: number)
		shakeAmount = math.max(shakeAmount, strength)
	end)
end

function CameraController.Start()
	RunService:BindToRenderStep("CrazyFareCamera", Enum.RenderPriority.Camera.Value, function(dt: number)
		camera.CameraType = Enum.CameraType.Scriptable
		follow(dt)
	end)
end

return CameraController
