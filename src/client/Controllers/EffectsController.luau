--!strict
-- Local VFX: windshield splat + wipers (honk shortens), destination beacon, item-box spin, tomato/banana bursts,
-- boost particles, honk bubble. Nothing here affects gameplay.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)
local InputController = require(script.Parent.InputController)

local EffectsController = {}

local splatScreen: ScreenGui
local blobs: { Frame } = {}
local beacon: Part? = nil
local boostEmitter: ParticleEmitter? = nil
local boxBases: { [BasePart]: CFrame } = {}
local rng = Random.new()

local function clearSplat()
	for _, blob in blobs do
		blob:Destroy()
	end
	table.clear(blobs)
end

-- Cover roughly `coverage` of the screen with red blobs.
local function makeSplat(coverage: number)
	clearSplat()
	local count = math.round(10 + coverage * 26)
	for _ = 1, count do
		local size = rng:NextNumber(0.12, 0.34) * (0.6 + coverage)
		local blob = UI.Frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rng:NextNumber(0.02, 0.98), rng:NextNumber(0.02, 0.98)),
			Size = UDim2.fromScale(size, size * rng:NextNumber(1.2, 1.9)),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			BackgroundColor3 = Color3.fromRGB(rng:NextInteger(170, 230), rng:NextInteger(20, 50), rng:NextInteger(20, 45)),
			BackgroundTransparency = rng:NextNumber(0.05, 0.3),
			Rotation = rng:NextNumber(0, 360),
		}, splatScreen)
		UI.Corner(999, blob)
		table.insert(blobs, blob)
	end
end

local function updateSplat()
	if #blobs == 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	local total = math.max(0.01, State.splatUntil - State.splatStartedAt)
	local progress = math.clamp((now - State.splatStartedAt) / total, 0, 1)
	if progress >= 1 then
		clearSplat()
		return
	end
	-- Wipers: blobs thin out from the top down as the wipe progresses.
	for _, blob in blobs do
		local y = blob.Position.Y.Scale
		local wiped = math.clamp((progress * 1.3 - y) / 0.3, 0, 1)
		blob.BackgroundTransparency = math.max(blob.BackgroundTransparency, wiped)
	end
end

local function setBeacon(fare: State.FareInfo?)
	if beacon then
		beacon:Destroy()
		beacon = nil
	end
	if not fare then
		return
	end
	local color = (Config.Fares.Tiers[fare.tier] or Config.Fares.Tiers.Green).Color
	local h = Config.Hud.BeaconHeight
	local part = Instance.new("Part")
	part.Name = "DestinationBeacon"
	part.Size = Vector3.new(4, h, 4)
	part.CFrame = CFrame.new(fare.destination + Vector3.new(0, h / 2, 0))
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = 0.55
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = workspace
	local gui = UI.New("BillboardGui", {
		Size = UDim2.fromOffset(160, 40),
		StudsOffset = Vector3.new(0, h / 2 + 4, 0),
		AlwaysOnTop = true,
		MaxDistance = 2000,
	}, part)
	UI.Label({ Size = UDim2.fromScale(1, 1), Text = "DROP HERE", TextColor3 = color }, gui)
	beacon = part
end

local function burst(position: Vector3, color: Color3)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2, 2, 2)
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = workspace
	TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(10, 10, 10),
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, 0.4)
end

local function honkBubble()
	local ch = State.chassis
	if not ch then
		return
	end
	local gui = UI.New("BillboardGui", {
		Size = UDim2.fromOffset(100, 30),
		StudsOffset = Vector3.new(0, 4, 0),
		AlwaysOnTop = true,
	}, ch)
	UI.Label({ Size = UDim2.fromScale(1, 1), Text = "HONK!", TextColor3 = UI.Warn }, gui)
	Debris:AddItem(gui, 0.5)
end

local function attachBoostEmitter(model: Model?)
	boostEmitter = nil
	if not model or not model.PrimaryPart then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BoostTrail"
	emitter.Enabled = false
	emitter.Rate = 120
	emitter.Lifetime = NumberRange.new(0.25, 0.45)
	emitter.Speed = NumberRange.new(20, 35)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 120, 30))
	emitter.LightEmission = 1
	emitter.EmissionDirection = Enum.NormalId.Back
	emitter.Parent = model.PrimaryPart
	boostEmitter = emitter
end

local function spinBoxes(dt: number)
	local t = os.clock()
	for _, inst in CollectionService:GetTagged(Config.Tags.ItemBox) do
		if not inst:IsA("BasePart") then
			continue
		end
		local base = boxBases[inst]
		if not base then
			base = inst.CFrame
			boxBases[inst] = base
		end
		local active = inst:GetAttribute("Active") ~= false
		inst.Transparency = if active then 0.1 else 0.85
		inst.CFrame = base * CFrame.new(0, math.sin(t * 2) * 0.5, 0) * CFrame.Angles(t * Config.Items.BoxSpinSpeed * 0.6, t * Config.Items.BoxSpinSpeed, 0)
	end
	local _ = dt
end

local function onItem(payload: Types.ItemEventPayload)
	if payload.kind == "Splat" then
		makeSplat(payload.coverage or Config.Items.Tomato.SplatCoverage)
	elseif payload.kind == "Burst" and payload.position then
		local def = Config.Items.Pool[payload.item or ""]
		burst(payload.position, if def then def.Color else UI.White)
	end
end

function EffectsController.Init()
	splatScreen = UI.Screen("CrazyFareSplat", 20)
	State.ItemEvent:Connect(onItem)
	State.FareEvent:Connect(function(payload: Types.FareEventPayload)
		if payload.kind == "Claimed" then
			setBeacon(State.fare)
		elseif payload.kind == "Delivered" or payload.kind == "Bailed" then
			setBeacon(nil)
		end
	end)
	State.RoundChanged:Connect(function(payload: Types.RoundStatePayload)
		if payload.phase ~= "Playing" then
			setBeacon(nil)
			clearSplat()
		end
	end)
	State.VehicleChanged:Connect(attachBoostEmitter)
	if State.vehicle then
		attachBoostEmitter(State.vehicle)
	end
	InputController.OnHonk:Connect(function()
		State.Honk:Fire()
		honkBubble()
		if #blobs > 0 then
			State.splatUntil -= Config.Items.Tomato.HonkWipeBonus
		end
	end)
	InputController.OnItem:Connect(function()
		if State.item ~= "" then
			Remotes.Get("UseItem"):FireServer()
		end
	end)
end

function EffectsController.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		updateSplat()
		spinBoxes(dt)
		if boostEmitter then
			boostEmitter.Enabled = State.boosting
		end
	end)
end

return EffectsController
