--!strict
-- The weather's falling part (Config.Chaos.Weather): rain or snow from a box that rides above your camera, so it's
-- always around you and costs nothing elsewhere. The sky itself (light, fog, tint) comes from the server
-- (WeatherService); the grip change lives in VehicleController; the banner in HudController.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)

local WeatherController = {}

local holder: Part
local emitter: ParticleEmitter
local shown = "" -- the Particle kind showing ("" = none)

local function setParticle(kind: string)
	if kind == shown then
		return
	end
	shown = kind
	local p: Config.WeatherParticles? = Config.Chaos.Weather.Particles[kind]
	if not p then
		emitter.Enabled = false
		emitter:Clear()
		return
	end
	holder.Size = Vector3.new(p.Area, 1, p.Area)
	emitter.Texture = p.Texture
	emitter.Color = ColorSequence.new(p.Color)
	emitter.Transparency = NumberSequence.new(p.Transparency)
	emitter.Size = NumberSequence.new(p.Size)
	emitter.Squash = NumberSequence.new(p.Squash)
	emitter.Rate = p.Rate
	emitter.Lifetime = NumberRange.new(p.Lifetime * 0.8, p.Lifetime * 1.2)
	emitter.Speed = NumberRange.new(p.SpeedMin, p.SpeedMax)
	emitter.Acceleration = p.Drift
	emitter.RotSpeed = NumberRange.new(-p.Spin, p.Spin)
	emitter.Orientation = if p.Streaks then Enum.ParticleOrientation.VelocityParallel else Enum.ParticleOrientation.FacingCamera
	emitter.Enabled = true
end

local function onRound(payload: Types.RoundStatePayload)
	local def: Config.WeatherDef? = nil
	for _, d in Config.Chaos.Weather.List do
		if d.Id == payload.weather then
			def = d
		end
	end
	setParticle(if def then def.Particle else "")
end

function WeatherController.Init()
	local part = Instance.new("Part")
	part.Name = "WeatherBox"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	holder = part
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Bottom
	e.LockedToPart = false
	e.LightInfluence = 0 -- bright against the dim sky, so it reads on a phone
	e.Enabled = false
	e.Parent = part
	emitter = e
	part.Parent = workspace
	State.RoundChanged:Connect(onRound)
end

function WeatherController.Start()
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		local cfg: Config.WeatherParticles? = Config.Chaos.Weather.Particles[shown]
		if camera and cfg then
			-- a little ahead of the camera, where you're looking, so it falls in front of you
			local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
			holder.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, cfg.Height, 0) + look * cfg.Ahead)
		end
	end)
end

return WeatherController
