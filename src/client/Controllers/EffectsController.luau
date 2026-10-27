--!strict
-- Local VFX: windshield splat + wipers (honk shortens), destination beacon (named) + glowing drop-off ring, rooftop name
-- signs over every drop-off, item-box spin, tomato/banana bursts, honk bubble. Boost flames and other speed effects
-- live in SpeedFxController. Nothing here affects gameplay.

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
local ring: Model? = nil

-- Rooftop name signs, one per drop-off; the current destination's lights up in its tier color.
type Sign = { gui: BillboardGui, frame: Frame, stroke: UIStroke, label: TextLabel, index: number }
local signs: { [BasePart]: Sign } = {}
local activeDestination = 0
local activeColor = UI.White
local SIGN_BACK = Color3.fromRGB(20, 20, 26)
local SIGN_EDGE = Color3.fromRGB(70, 72, 84)
local SIGN_TEXT = Color3.fromRGB(235, 235, 245)
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

local function styleSign(sign: Sign)
	local dest = Config.Destinations
	local active = sign.index == activeDestination
	local scale = if active then dest.SignActiveScale else 1
	sign.gui.Size = UDim2.fromScale(dest.SignWidth * scale, dest.SignHeightStuds * scale)
	sign.label.TextColor3 = if active then activeColor else SIGN_TEXT
	sign.stroke.Color = if active then activeColor else SIGN_EDGE
	sign.frame.BackgroundTransparency = if active then 0 else 0.2
end

local function addSign(inst: Instance)
	if not inst:IsA("BasePart") or signs[inst] then
		return
	end
	local part = inst :: BasePart
	local name = part:GetAttribute("Destination")
	local index = part:GetAttribute("Index")
	if typeof(name) ~= "string" or name == "" or typeof(index) ~= "number" then
		-- the name can land a moment after the part; try again when it does
		part:GetAttributeChangedSignal("Destination"):Once(function()
			addSign(part)
		end)
		return
	end
	local dest = Config.Destinations
	-- Hang the sign from a point straight above the marker. The markers are discs lying on their side, and a billboard's
	-- "world space" offset actually follows the part's own axes, so it would slide the sign sideways into the ground.
	local anchor = Instance.new("Attachment")
	anchor.Name = "DestinationSignAnchor"
	anchor.Position = part.CFrame:VectorToObjectSpace(Vector3.new(0, dest.SignHeight, 0))
	anchor.Parent = part
	local gui = UI.New("BillboardGui", {
		Name = "DestinationSign",
		Adornee = anchor,
		LightInfluence = 0,
		MaxDistance = dest.SignMaxDistance,
		AlwaysOnTop = false,
	}, part) :: BillboardGui
	local frame = UI.Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = SIGN_BACK }, gui)
	UI.Corner(8, frame)
	local stroke = UI.Stroke(SIGN_EDGE, 3, frame)
	local label = UI.Label({ Position = UDim2.fromScale(0.04, 0.1), Size = UDim2.fromScale(0.92, 0.8), Text = (string.gsub(name, "^THE ", "")) }, frame)
	local sign: Sign = { gui = gui, frame = frame, stroke = stroke, label = label, index = index }
	signs[part] = sign
	styleSign(sign)
end

local function setActiveDestination(index: number, color: Color3)
	activeDestination = index
	activeColor = color
	for _, sign in signs do
		styleSign(sign)
	end
end

-- The drop zone you have to stop in: a neon ring of segments hugging the ground at the delivery radius, and a pulsing disc.
local function clearRing()
	if ring then
		ring:Destroy()
		ring = nil
	end
end

local function buildRing(center: Vector3, color: Color3)
	clearRing()
	local cfg = Config.Hud.DropRing
	local radius = Config.Fares.DeliverRadius
	local model = Instance.new("Model")
	model.Name = "DropRing"
	local map = workspace:FindFirstChild("Map")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if map then { map } else {}
	local function groundY(x: number, z: number): number
		local hit = workspace:Raycast(Vector3.new(x, center.Y + 20, z), Vector3.new(0, -60, 0), params)
		return if hit then hit.Position.Y else center.Y
	end
	local function piece(size: Vector3, cf: CFrame, transparency: number): Part
		local part = Instance.new("Part")
		part.Size = size
		part.CFrame = cf
		part.Color = color
		part.Material = Enum.Material.Neon
		part.Transparency = transparency
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
		return part
	end
	local segment = 2 * math.pi * radius / cfg.Segments * 1.05
	for i = 0, cfg.Segments - 1 do
		local a = (i + 0.5) / cfg.Segments * 2 * math.pi
		local x, z = center.X + math.cos(a) * radius, center.Z + math.sin(a) * radius
		local y = groundY(x, z) + cfg.Thickness / 2 + 0.05
		piece(Vector3.new(cfg.Width, cfg.Thickness, segment), CFrame.new(x, y, z) * CFrame.Angles(0, -a, 0), cfg.Transparency)
	end
	local disc = piece(Vector3.new(cfg.Thickness, radius * 2, radius * 2), CFrame.new(center.X, groundY(center.X, center.Z) + 0.08, center.Z) * CFrame.Angles(0, 0, math.pi / 2), cfg.DiscTransparency)
	disc.Shape = Enum.PartType.Cylinder
	TweenService:Create(disc, TweenInfo.new(cfg.PulseSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = math.min(1, cfg.DiscTransparency + 0.12) }):Play()
	model.Parent = workspace
	ring = model
end

local function setBeacon(fare: State.FareInfo?)
	if beacon then
		beacon:Destroy()
		beacon = nil
	end
	if not fare then
		clearRing()
		setActiveDestination(0, UI.White)
		return
	end
	local color = if fare.golden then Config.Golden.Color else (Config.Fares.Tiers[fare.tier] or Config.Fares.Tiers.Green).Color
	buildRing(fare.destination, color)
	setActiveDestination(fare.destinationIndex, color)
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
	UI.Label({ Size = UDim2.fromScale(1, 1), Text = if fare.destinationName ~= "" then fare.destinationName else "DROP HERE", TextColor3 = color }, gui)
	beacon = part
end

-- Big glowing arrow over the local cab that points at the destination (local-only parts, nobody else sees it).
local arrowFolder: Folder? = nil
local arrowParts: { BasePart } = {}
local arrowLabel: TextLabel? = nil

local function destroyArrow()
	if arrowFolder then
		arrowFolder:Destroy()
		arrowFolder = nil
	end
	arrowParts = {}
	arrowLabel = nil
end

local function buildArrow(color: Color3)
	destroyArrow()
	local a = Config.Hud.Arrow
	local folder = Instance.new("Folder")
	folder.Name = "DestinationArrow"
	local function piece(size: Vector3, offset: CFrame): BasePart
		local part = Instance.new("Part")
		part.Size = size
		part.Color = color
		part.Material = Enum.Material.Neon
		part.Transparency = a.Transparency
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part:SetAttribute("Offset", offset)
		part.Parent = folder
		table.insert(arrowParts, part)
		return part
	end
	-- Shaft plus a chevron head; the arrow points along its local -Z.
	local shaft = piece(Vector3.new(a.Width, a.Thickness, a.Length), CFrame.new(0, 0, a.Length * 0.25))
	piece(Vector3.new(a.Width, a.Thickness, a.Length * 0.55), CFrame.new(-a.Width * 1.1, 0, -a.Length * 0.35) * CFrame.Angles(0, -math.rad(40), 0))
	piece(Vector3.new(a.Width, a.Thickness, a.Length * 0.55), CFrame.new(a.Width * 1.1, 0, -a.Length * 0.35) * CFrame.Angles(0, math.rad(40), 0))
	local gui = UI.New("BillboardGui", {
		Size = UDim2.fromOffset(150, 52),
		StudsOffset = Vector3.new(0, 2, 0),
		AlwaysOnTop = true,
		MaxDistance = 500,
	}, shaft)
	arrowLabel = UI.Label({ Size = UDim2.fromScale(1, 1), Text = "", TextColor3 = color }, gui)
	folder.Parent = workspace
	arrowFolder = folder
end

local function updateArrow()
	local fare = State.fare
	local ch = State.chassis
	if not fare or not ch or not ch:IsDescendantOf(workspace) then
		if arrowFolder then
			destroyArrow()
		end
		return
	end
	if not arrowFolder then
		buildArrow((Config.Fares.Tiers[fare.tier] or Config.Fares.Tiers.Green).Color)
	end
	local a = Config.Hud.Arrow
	local base = ch.Position + Vector3.new(0, a.Height + math.sin(os.clock() * 3) * 0.4, 0)
	local toDest = Vector3.new(fare.destination.X - ch.Position.X, 0, fare.destination.Z - ch.Position.Z)
	local dist = toDest.Magnitude
	local dir = if dist > 0.5 then toDest.Unit else Vector3.new(0, 0, -1)
	local root = CFrame.lookAt(base, base + dir) * CFrame.Angles(-math.rad(a.Pitch), 0, 0)
	for _, part in arrowParts do
		local offset = part:GetAttribute("Offset")
		if typeof(offset) == "CFrame" then
			part.CFrame = root * offset
		end
	end
	if arrowLabel then
		local look = Vector3.new(ch.CFrame.LookVector.X, 0, ch.CFrame.LookVector.Z)
		look = if look.Magnitude > 0.01 then look.Unit else dir
		local angle = math.deg(math.atan2(look:Cross(dir).Y, look:Dot(dir)))
		local word = ""
		if dist <= Config.Fares.DeliverRadius then
			word = "STOP"
		elseif math.abs(angle) >= Config.Hud.Arrow.TurnAroundDegrees then
			word = "TURN AROUND"
		elseif math.abs(angle) >= Config.Hud.Arrow.SideDegrees then
			word = if angle < 0 then "RIGHT" else "LEFT"
		end
		arrowLabel.Text = if word == "" then string.format("%d", math.round(dist)) else word .. "\n" .. string.format("%d", math.round(dist))
	end
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
	splatScreen = UI.Screen("CrazyFareSplat", 20, true)
	for _, part in CollectionService:GetTagged(Config.Tags.DropoffPoint) do
		addSign(part)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.DropoffPoint):Connect(addSign)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.DropoffPoint):Connect(function(inst: Instance)
		if inst:IsA("BasePart") then
			signs[inst] = nil
		end
	end)
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
	InputController.OnHonk:Connect(function()
		State.Honk:Fire()
		honkBubble()
		if #blobs > 0 then
			State.splatUntil -= Config.Items.Tomato.HonkWipeBonus
		end
	end)
	InputController.OnItem:Connect(function()
		print(string.format("[Effects] Q pressed, holding %q", State.item))
		if State.item ~= "" then
			Remotes.Get("UseItem"):FireServer()
		end
	end)
end

function EffectsController.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		updateSplat()
		updateArrow()
		spinBoxes(dt)
	end)
end

return EffectsController
