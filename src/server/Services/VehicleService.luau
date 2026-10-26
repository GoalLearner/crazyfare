--!strict
-- Spawns one taxi per player, hands physics to that player, freezes/releases cars with the round,
-- and watches replicated velocity for crashes. Vehicle stats come from Config; the model from the template or VehicleBuilder.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local VehicleBuilder = require(ReplicatedStorage.Shared.VehicleBuilder)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local MapService = require(script.Parent.MapService)
local DataService = require(script.Parent.DataService)

export type VehicleEntry = {
	player: Player,
	model: Model,
	chassis: BasePart,
	vehicleId: string,
	slot: number,
	lastVelocity: Vector3,
	drifting: boolean, -- client-reported; Tomato loses lock on drifting targets
	boostUntil: number, -- server time; speed sanity allowance
	spinUntil: number, -- server time; crash detection ignores spinouts
	crashImmuneUntil: number,
	lastPosition: Vector3, -- last position that passed speed sanity
	strikes: number, -- consecutive frames that failed it
}

local VehicleService = {}

local onCrash: Signal.Signal<Player, number> = Signal.new()
local onSpawned: Signal.Signal<Player, VehicleEntry> = Signal.new()
VehicleService.OnCrash = onCrash -- (player, horizontal velocity delta in studs/s)
VehicleService.OnSpawned = onSpawned

local entries: { [Player]: VehicleEntry } = {}
local released = false
local folder: Folder

local function freeSlot(): number
	local used: { [number]: boolean } = {}
	for _, entry in entries do
		used[entry.slot] = true
	end
	for i = 1, 64 do
		if not used[i] then
			return i
		end
	end
	return 1
end

local function padCFrameForSlot(slot: number): CFrame
	local pads = MapService.GetStartPads()
	if #pads == 0 then
		return CFrame.new(0, 4, 0)
	end
	local pad = pads[((slot - 1) % #pads) + 1]
	return pad.cframe * CFrame.new(0, 3.2, 0)
end

local function buildModel(vehicleId: string): Model
	local templates = ReplicatedStorage:FindFirstChild("VehicleTemplates")
	local template = if templates then templates:FindFirstChild(vehicleId) else nil
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return VehicleBuilder.Build(vehicleId)
end

local function applyRelease(entry: VehicleEntry)
	if released then
		entry.chassis.Anchored = false
		local ok, err = pcall(function()
			entry.chassis:SetNetworkOwner(entry.player)
		end)
		if not ok then
			warn("[VehicleService] SetNetworkOwner failed for " .. entry.player.Name .. ": " .. tostring(err))
		end
	else
		entry.chassis.Anchored = true
	end
end

function VehicleService.GetEntry(player: Player): VehicleEntry?
	return entries[player]
end

function VehicleService.GetAll(): { [Player]: VehicleEntry }
	return entries
end

function VehicleService.GetPosition(player: Player): Vector3?
	local entry = entries[player]
	return if entry then entry.chassis.Position else nil
end

function VehicleService.GetSpeed(player: Player): number
	local entry = entries[player]
	return if entry then entry.chassis.AssemblyLinearVelocity.Magnitude else 0
end

function VehicleService.IsReleased(): boolean
	return released
end

function VehicleService.SetSilhouette(player: Player, visible: boolean)
	local entry = entries[player]
	if not entry then
		return
	end
	local silhouette = entry.model:FindFirstChild("Silhouette")
	if silhouette and silhouette:IsA("BasePart") then
		silhouette.Transparency = if visible then 0 else 1
	end
end

-- Glow on a car for a defense item. color nil removes it; seconds 0 keeps it until removed.
function VehicleService.SetHighlight(player: Player, color: Color3?, seconds: number)
	local entry = entries[player]
	if not entry then
		return
	end
	local existing = entry.model:FindFirstChild("DefenseGlow")
	if existing then
		existing:Destroy()
	end
	if not color then
		return
	end
	local glow = Instance.new("Highlight")
	glow.Name = "DefenseGlow"
	glow.FillColor = color
	glow.FillTransparency = 0.6
	glow.OutlineColor = color
	glow.OutlineTransparency = 0
	glow.Parent = entry.model
	if seconds > 0 then
		task.delay(seconds, function()
			if glow.Parent then
				glow:Destroy()
			end
		end)
	end
end

-- Exclusive trail for this week's leaderboard top: two attachments at the rear corners and a Trail between them.
local function applyTrail(entry: VehicleEntry)
	local existing = entry.model:FindFirstChild("WeeklyTrail")
	if existing then
		existing:Destroy()
	end
	if entry.player:GetAttribute("WeeklyTrail") ~= true then
		return
	end
	local size = entry.chassis.Size
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailL"
	a0.Position = Vector3.new(-size.X / 2, 0, size.Z / 2)
	a0.Parent = entry.chassis
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailR"
	a1.Position = Vector3.new(size.X / 2, 0, size.Z / 2)
	a1.Parent = entry.chassis
	local trail = Instance.new("Trail")
	trail.Name = "WeeklyTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 215, 80), Color3.fromRGB(255, 120, 30))
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.6
	trail.LightEmission = 0.8
	trail.MinLength = 0.2
	trail.Parent = entry.model
end

function VehicleService.Despawn(player: Player)
	local entry = entries[player]
	if not entry then
		return
	end
	entries[player] = nil
	entry.model:Destroy()
end

function VehicleService.Spawn(player: Player)
	if entries[player] then
		VehicleService.Despawn(player)
	end
	local vehicleId = DataService.GetSelectedVehicle(player)
	local model = buildModel(vehicleId)
	VehicleBuilder.ApplyPaint(model, DataService.GetPaint(player))
	local chassis = model.PrimaryPart
	if not chassis then
		warn("[VehicleService] vehicle model has no PrimaryPart: " .. vehicleId)
		model:Destroy()
		return
	end
	local slot = freeSlot()
	model.Name = player.Name .. "_" .. vehicleId
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerName", player.Name)
	CollectionService:AddTag(model, Config.Tags.Vehicle)
	chassis.Anchored = true
	model:PivotTo(padCFrameForSlot(slot))
	model.Parent = folder

	local entry: VehicleEntry = {
		player = player,
		model = model,
		chassis = chassis,
		vehicleId = vehicleId,
		slot = slot,
		lastVelocity = Vector3.zero,
		drifting = false,
		boostUntil = 0,
		spinUntil = 0,
		crashImmuneUntil = 0,
		lastPosition = chassis.Position,
		strikes = 0,
	}
	entries[player] = entry
	applyRelease(entry)
	applyTrail(entry)
	Remotes.Get("VehicleAssigned"):FireClient(player, model)
	onSpawned:Fire(player, entry)
end

-- Put a car back on its grid pad, frozen, with clean state.
function VehicleService.PlaceOnGrid(entry: VehicleEntry)
	entry.chassis.Anchored = true
	entry.chassis.AssemblyLinearVelocity = Vector3.zero
	entry.chassis.AssemblyAngularVelocity = Vector3.zero
	entry.model:PivotTo(padCFrameForSlot(entry.slot))
	entry.lastVelocity = Vector3.zero
	entry.boostUntil = 0
	entry.spinUntil = 0
	entry.drifting = false
	entry.crashImmuneUntil = workspace:GetServerTimeNow() + Config.Passenger.DamageCooldown
	VehicleService.SetSilhouette(entry.player, false)
end

function VehicleService.ResetAllToGrid()
	released = false
	for player, entry in entries do
		if DataService.GetSelectedVehicle(player) ~= entry.vehicleId then
			VehicleService.Spawn(player) -- garage choice takes effect between rounds
		else
			VehicleService.PlaceOnGrid(entry)
		end
	end
end

-- true = cars unanchored and owned by their players; false = frozen where they are.
function VehicleService.SetReleased(value: boolean)
	released = value
	for _, entry in entries do
		applyRelease(entry)
	end
end

-- Teleport a live car (server write replicates to the owner as a teleport).
function VehicleService.Teleport(entry: VehicleEntry, cframe: CFrame)
	entry.chassis.AssemblyLinearVelocity = Vector3.zero
	entry.chassis.AssemblyAngularVelocity = Vector3.zero
	entry.model:PivotTo(cframe)
	entry.lastVelocity = Vector3.zero
	entry.lastPosition = entry.chassis.Position
	entry.strikes = 0
	entry.crashImmuneUntil = workspace:GetServerTimeNow() + Config.Passenger.DamageCooldown
end

-- Reset request: stand the car upright a little above the ground where it is, keeping its heading.
local function resetVehicle(player: Player)
	local entry = entries[player]
	if not entry or entry.chassis.Anchored then
		return
	end
	local cf = entry.chassis.CFrame
	local look = VecUtil.FlatUnit(cf.LookVector)
	local groundY = MapService.GroundY(cf.Position, cf.Position.Y)
	local pos = Vector3.new(cf.Position.X, groundY + Config.Chassis.ResetLift, cf.Position.Z)
	VehicleService.Teleport(entry, CFrame.lookAt(pos, pos + look))
end

function VehicleService.Init()
	folder = MapService.GetRuntimeFolder("Vehicles")

	Remotes.Get("DriveState").OnServerEvent:Connect(function(player: Player, drifting: any)
		if not RateLimiter.Allow(player, "DriveState", Config.Net.RateLimits.DriveState) then
			return
		end
		local entry = entries[player]
		if entry then
			entry.drifting = drifting == true
		end
	end)

	Remotes.Get("ResetVehicle").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "ResetVehicle", Config.Net.RateLimits.ResetVehicle) then
			return
		end
		resetVehicle(player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		VehicleService.Spawn(player)
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		player:GetAttributeChangedSignal("WeeklyTrail"):Connect(function()
			local entry = entries[player]
			if entry then
				applyTrail(entry)
			end
		end)
	end)
	-- A garage change while the car is parked (lobby, pit stop) swaps it right away; mid-round it waits for the grid.
	DataService.OnVehicleSelected:Connect(function(player: Player)
		local entry = entries[player]
		if not entry then
			return
		end
		if released and not entry.chassis.Anchored then
			VehicleBuilder.ApplyPaint(entry.model, DataService.GetPaint(player))
		else
			VehicleService.Spawn(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		VehicleService.Despawn(player)
		RateLimiter.Clear(player)
	end)
end

function VehicleService.Start()
	for _, player in Players:GetPlayers() do
		if not entries[player] then
			VehicleService.Spawn(player)
		end
	end

	-- Crash watch: horizontal velocity delta between server frames. Jumps and landings are free; walls are not.
	-- Speed sanity: a car that covers more ground per frame than its fastest legal speed allows, several frames
	-- in a row, is put back where it was last seen behaving.
	local sanity = Config.Net.SpeedSanity
	RunService.Heartbeat:Connect(function(dt: number)
		local now = workspace:GetServerTimeNow()
		for player, entry in entries do
			if entry.chassis.Anchored then
				entry.lastVelocity = Vector3.zero
				entry.lastPosition = entry.chassis.Position
				entry.strikes = 0
				continue
			end
			local v = entry.chassis.AssemblyLinearVelocity
			local delta = VecUtil.FlatDistance(v, entry.lastVelocity)
			entry.lastVelocity = v
			local boostEnding = now >= entry.boostUntil and now - entry.boostUntil < Config.Passenger.BoostEndGrace
			if delta >= Config.Passenger.CrashDeltaThreshold and now >= entry.crashImmuneUntil and now >= entry.spinUntil and not boostEnding then
				onCrash:Fire(player, delta)
			end

			local pos = entry.chassis.Position
			local stats = Config.Vehicles.Stats[entry.vehicleId] or Config.Vehicles.Stats[Config.Vehicles.Default]
			local legalSpeed = stats.TopSpeed * Config.Items.LemonNitro.SpeedMult * Config.Chassis.BoostSpeedMult * Config.Chassis.SpeedHardCapMult * Config.PitStop.Cards.SpeedTune.Value * (1 + Config.Upgrades.Speed.Per * Config.Upgrades.Speed.Max)
			local moved = VecUtil.FlatDistance(pos, entry.lastPosition)
			if moved > legalSpeed * dt + sanity.Slack and now >= entry.crashImmuneUntil then
				entry.strikes += 1
				if entry.strikes >= sanity.Strikes then
					warn(string.format("[VehicleService] speed sanity: %s moved %.1f studs in one frame, correcting", player.Name, moved))
					entry.strikes = 0
					local look = VecUtil.FlatUnit(entry.chassis.CFrame.LookVector)
					VehicleService.Teleport(entry, CFrame.lookAt(entry.lastPosition, entry.lastPosition + look))
					continue
				end
			else
				entry.strikes = 0
				entry.lastPosition = pos
			end
		end
	end)
end

return VehicleService
