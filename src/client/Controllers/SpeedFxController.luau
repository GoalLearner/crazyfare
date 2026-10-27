--!strict
-- Speed feel for the local cab, all client-side: exhaust flames and a flickering glow while boosting (Shift, Lemon
-- Nitro, Dash), streaks racing out from the middle of the screen near top speed, a ring of cartoon dust puffs on
-- landing, puffs of tire smoke while drifting. Nothing here affects gameplay; every number is Config.SpeedFx.
-- Dust and smoke are little balls that swell and fade (they read on pale roads and match the blocky city, where soft
-- particle smoke vanishes).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local SpeedFxController = {}

type Streak = { frame: Frame, angle: number, progress: number, pace: number }

local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local FLAME_COLORS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 210)),
	ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 190, 60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 20)),
})
local FLAME_GLOW = Color3.fromRGB(255, 150, 50)
local SMOKE_COLOR = Color3.fromRGB(232, 232, 236)
local DUST_TINT = Color3.fromRGB(140, 130, 115) -- landing dust is the ground's color pulled toward a dusty brown-grey,
local DUST_TINT_MIX = 0.45 -- so it still reads on pale concrete and sand

local owned: { Instance } = {} -- attachments made on the current cab; destroyed with it
local flames: { ParticleEmitter } = {}
local flameLight: PointLight? = nil
local smokePoints: { Attachment } = {} -- rear tire contact patches
local smokeDue = 0 -- seconds until the next pair of smoke puffs
local puffFolder: Folder? = nil
local streakLayer: Frame
local streaks: { Streak } = {}
local streakIntensity = 0
local rng = Random.new()
local groundParams = RaycastParams.new()

local function sequence(from: number, to: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, from), NumberSequenceKeypoint.new(1, to) })
end

local function folder(): Folder
	local existing = puffFolder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "SpeedFx"
	made.Parent = workspace
	puffFolder = made
	return made
end

-- One cartoon puff: a ball that drifts, swells and fades, then cleans itself up.
local function puff(position: Vector3, color: Color3, startSize: number, endSize: number, drift: Vector3, seconds: number, opacity: number)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * startSize
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 1 - opacity
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder()
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * endSize,
		CFrame = CFrame.new(position + drift * seconds),
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, seconds + 0.05)
end

local function clearVehicleFx()
	for _, inst in owned do
		inst:Destroy()
	end
	table.clear(owned)
	table.clear(flames)
	table.clear(smokePoints)
	flameLight = nil
end

local function attachment(chassis: BasePart, name: string, position: Vector3): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.Position = position
	att.Parent = chassis
	table.insert(owned, att)
	return att
end

local function attach(model: Model?)
	clearVehicleFx()
	local chassis = if model then model.PrimaryPart else nil
	if not chassis then
		return
	end
	local size = chassis.Size

	-- Two exhaust flames out the back (models face -Z, so the back is +Z and EmissionDirection Back points out of it)
	local f = Config.SpeedFx.Flames
	for _, side in { -1, 1 } do
		local att = attachment(chassis, "BoostFlame", Vector3.new(side * size.X * 0.22, -size.Y * 0.2, size.Z / 2 + 0.2))
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = FIRE_TEXTURE
		emitter.Enabled = false
		emitter.Rate = f.Rate
		emitter.Lifetime = NumberRange.new(f.Lifetime * 0.7, f.Lifetime * 1.3)
		emitter.Speed = NumberRange.new(f.Speed * 0.7, f.Speed)
		emitter.SpreadAngle = Vector2.new(f.Spread, f.Spread)
		emitter.Size = sequence(f.Size, f.Size * 0.15)
		emitter.Transparency = sequence(0.05, 1)
		emitter.Color = FLAME_COLORS
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.EmissionDirection = Enum.NormalId.Back
		emitter.Parent = att
		table.insert(flames, emitter)
		if not flameLight then
			local light = Instance.new("PointLight")
			light.Color = FLAME_GLOW
			light.Range = f.LightRange
			light.Brightness = f.LightBrightness
			light.Enabled = false
			light.Parent = att
			flameLight = light
		end
	end

	-- Where tire smoke comes from: the rear wheels' contact patches
	local drop = Config.Chassis.SuspensionRest * 0.6 + Config.Chassis.WheelRadius * 0.7
	for _, wheelName in { "WheelRL", "WheelRR" } do
		local wheel = chassis:FindFirstChild(wheelName)
		local base = if wheel and wheel:IsA("Attachment") then wheel.Position else Vector3.new(0, 0, size.Z / 2)
		table.insert(smokePoints, attachment(chassis, "DriftSmoke", base - Vector3.new(0, drop, 0)))
	end
end

-- Touchdown: a ring of dust puffs rolls out across the ground, sized by the air time, and the camera thumps.
local function onLanded(airSeconds: number)
	local chassis = State.chassis
	if not chassis then
		return
	end
	local d = Config.SpeedFx.Dust
	local map = workspace:FindFirstChild("Map")
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = if map then { map } else {}
	local hit = workspace:Raycast(chassis.Position, Vector3.new(0, -12, 0), groundParams)
	local ground = if hit then hit.Position else chassis.Position - Vector3.new(0, chassis.Size.Y, 0)
	local color = (if hit then hit.Instance.Color else SMOKE_COLOR):Lerp(DUST_TINT, DUST_TINT_MIX)
	local count = math.round(math.clamp(d.MinPuffs + airSeconds * d.PerAirSecond, d.MinPuffs, d.MaxPuffs))
	local offset = rng:NextNumber(0, math.pi * 2)
	for i = 1, count do
		local angle = offset + (i / count) * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local start = ground + out * chassis.Size.X * 0.4 + Vector3.new(0, d.GroundLift, 0)
		local speed = d.Speed * rng:NextNumber(0.75, 1.15)
		puff(start, color, d.StartSize, d.EndSize * rng:NextNumber(0.8, 1.2), out * speed + Vector3.new(0, d.Rise, 0), d.Seconds * rng:NextNumber(0.85, 1.15), d.Opacity)
	end
	State.Shake:Fire(d.Shake * math.clamp(airSeconds / d.ShakeAirSeconds, 0.3, 1))
end

local function onDashed()
	for _, emitter in flames do
		emitter:Emit(25)
	end
end

-- While drifting, each rear tire coughs up a smoke puff Rate times a second.
local function updateSmoke(dt: number)
	if not State.drifting or #smokePoints == 0 then
		smokeDue = 0
		return
	end
	smokeDue -= dt
	if smokeDue > 0 then
		return
	end
	local s = Config.SpeedFx.Smoke
	smokeDue = 1 / s.Rate
	for _, point in smokePoints do
		local jitter = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * s.Spread
		local drift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * s.Spread + Vector3.new(0, s.Rise, 0)
		puff(point.WorldPosition + jitter, SMOKE_COLOR, s.StartSize, s.EndSize * rng:NextNumber(0.8, 1.2), drift, s.Seconds * rng:NextNumber(0.8, 1.2), s.Opacity)
	end
end

local function buildStreaks()
	local screen = UI.Screen("CrazyFareSpeed", 5, true) -- under the HUD; streaks are laid out in real pixels
	streakLayer = UI.Frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, screen)
	for _ = 1, Config.SpeedFx.Streaks.Count do
		local frame = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = UI.White, BackgroundTransparency = 1, BorderSizePixel = 0 }, streakLayer)
		table.insert(streaks, { frame = frame, angle = rng:NextNumber(0, math.pi * 2), progress = rng:NextNumber(), pace = rng:NextNumber(0.8, 1.25) })
	end
end

-- Streaks race outward from a ring around the cab; how many you see and how bright follows speed (and boost).
local function updateStreaks(dt: number)
	local cfg = Config.SpeedFx.Streaks
	local speedFrac = math.clamp(State.speed / State.stats.TopSpeed, 0, 1.5)
	local target = math.clamp((speedFrac - cfg.StartFrac) / (1 - cfg.StartFrac), 0, 1)
	if State.boosting and speedFrac > cfg.StartFrac * 0.5 then
		target = math.min(1, target + cfg.BoostBonus)
	end
	streakIntensity += (target - streakIntensity) * math.clamp(dt * 6, 0, 1)
	if streakIntensity < 0.02 then
		streakLayer.Visible = false
		return
	end
	streakLayer.Visible = true
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local center = view / 2
	local reach = view.Magnitude / 2
	for _, streak in streaks do
		streak.progress += dt / cfg.Seconds * streak.pace
		if streak.progress >= 1 then
			streak.progress -= 1
			streak.angle = rng:NextNumber(0, math.pi * 2)
		end
		local p = streak.progress
		local dir = Vector2.new(math.cos(streak.angle), math.sin(streak.angle))
		local pos = center + dir * reach * (cfg.InnerRadius + (1 - cfg.InnerRadius) * p)
		local frame = streak.frame
		frame.Position = UDim2.fromOffset(pos.X, pos.Y)
		frame.Size = UDim2.fromOffset(cfg.Length * streakIntensity * (0.5 + p), cfg.Thickness)
		frame.Rotation = math.deg(streak.angle)
		frame.BackgroundTransparency = 1 - cfg.MaxOpacity * streakIntensity * math.sin(math.pi * p)
	end
end

function SpeedFxController.Init()
	buildStreaks()
	State.VehicleChanged:Connect(attach)
	if State.vehicle then
		attach(State.vehicle)
	end
	State.Landed:Connect(onLanded)
	State.Hopped:Connect(function()
		onLanded(0) -- the smallest ring of dust as you leave the ground
	end)
	State.Dashed:Connect(onDashed)
end

function SpeedFxController.Start()
	RunService.RenderStepped:Connect(function(dt: number)
		local boosting = State.boosting and State.chassis ~= nil
		for _, emitter in flames do
			emitter.Enabled = boosting
		end
		local light = flameLight
		if light then
			light.Enabled = boosting
			if boosting then
				light.Brightness = Config.SpeedFx.Flames.LightBrightness * rng:NextNumber(0.75, 1.25)
			end
		end
		updateSmoke(dt)
		updateStreaks(dt)
	end)
end

return SpeedFxController
