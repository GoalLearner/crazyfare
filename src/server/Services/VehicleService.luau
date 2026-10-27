--!strict
-- Spawns one taxi per player, hands physics to that player, freezes/releases cars with the round,
-- and watches replicated velocity for crashes. Vehicle stats come from Config; the model from the template or VehicleBuilder.
-- AI rival taxis get entries too (SpawnBot, keyed by their Racers stand-in): same grid, crash watch and item rules, but
-- the server keeps their physics and BotService steers them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
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
	lockedBy: Player?, -- the rival whose Banana or Oil Slick has this car spinning or unsteerable...
	lockedUntil: number, -- ...until this server time (a pedestrian clip in that window is theirs)
	crashImmuneUntil: number,
	speedHistory: { { t: number, speed: number } }, -- recent horizontal speeds for the crash watch
	impact: { peak: number, low: number, settleAt: number, bonus: number }?, -- a hit in progress, measured until settleAt so the whole stop counts; bonus = biggest reported contact speed (traffic)
	lastPosition: Vector3, -- last position that passed speed sanity
	strikes: number, -- consecutive frames that failed it
	isBot: boolean, -- an AI rival taxi (server-owned physics, never sent anything)
	paint: Color3?, -- a bot's paint, kept for respawns
}

local VehicleService = {}

local onCrash: Signal.Signal<Player, number> = Signal.new()
local onSpawned: Signal.Signal<Player, VehicleEntry> = Signal.new()
VehicleService.OnCrash = onCrash -- (player, horizontal speed lost in studs/s)
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

-- Why a template cannot be used, or nil when it satisfies the VehicleBuilder contract.
local function templateProblem(template: Instance): string?
	if not template:IsA("Model") then
		return "not a Model"
	end
	local chassis = template.PrimaryPart
	if not chassis then
		return "no PrimaryPart (needs a part named Chassis set as PrimaryPart)"
	end
	for _, name in { "WheelFL", "WheelFR", "WheelRL", "WheelRR", "DropPoint", "Muzzle" } do
		local att = chassis:FindFirstChild(name)
		if not att or not att:IsA("Attachment") then
			return "missing attachment " .. name .. " on the Chassis"
		end
	end
	local visible = 0
	for _, part in template:GetDescendants() do
		if part:IsA("BasePart") and part ~= chassis and part.Transparency < 1 then
			visible += 1
		end
	end
	if visible == 0 then
		return "no visible parts besides the Chassis"
	end
	return nil
end

local function buildModel(vehicleId: string): Model
	local templates = ReplicatedStorage:FindFirstChild("VehicleTemplates")
	local template = if templates then templates:FindFirstChild(vehicleId) else nil
	if template then
		local problem = templateProblem(template)
		if not problem then
			return (template :: Model):Clone()
		end
		warn(string.format("[VehicleService] template %s unusable (%s); using the parts build. Re-import and run VehicleRig again.", vehicleId, problem))
	end
	return VehicleBuilder.Build(vehicleId)
end

local function applyRelease(entry: VehicleEntry)
	if released then
		entry.chassis.Anchored = false
		local ok, err = pcall(function()
			entry.chassis:SetNetworkOwner(if entry.isBot then nil else entry.player)
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

-- How big an OnCrash was for this player's car: the share of its top speed the hit took (0 when there's no car).
function VehicleService.CrashIntensity(player: Player, lost: number): number
	local entry = entries[player]
	if not entry then
		return 0
	end
	local stats = Config.Vehicles.Stats[entry.vehicleId] or Config.Vehicles.Stats[Config.Vehicles.Default]
	return lost / stats.TopSpeed
end

-- A hit measured outside the speed watch (TrafficService reports how fast a player car closed on a traffic car).
-- It joins the crash watch so one hit fires once, with the bigger of the two readings.
function VehicleService.ReportImpact(player: Player, speed: number)
	local entry = entries[player]
	if not entry or entry.chassis.Anchored then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now < entry.crashImmuneUntil or now < entry.spinUntil then
		return
	end
	local impact = entry.impact
	if impact then
		impact.bonus = math.max(impact.bonus, speed)
		return
	end
	local v = entry.chassis.AssemblyLinearVelocity
	local current = Vector3.new(v.X, 0, v.Z).Magnitude
	entry.impact = { peak = current, low = current, settleAt = now + Config.Passenger.CrashSettle, bonus = speed }
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
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = Config.CollisionGroups.Vehicles -- traffic collides with this group only
		end
	end
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
		lockedBy = nil,
		lockedUntil = 0,
		crashImmuneUntil = 0,
		speedHistory = {},
		impact = nil,
		lastPosition = chassis.Position,
		strikes = 0,
		isBot = false,
		paint = nil,
	}
	entries[player] = entry
	applyRelease(entry)
	applyTrail(entry)
	Remotes.Get("VehicleAssigned"):FireClient(player, model)
	onSpawned:Fire(player, entry)
end

-- An AI rival's taxi: the parts build of the vehicle (paint takes on every panel, so each bot has its own color; the
-- imported cab mesh keeps its yellow texture), on a free grid pad, in the Bots collision group.
function VehicleService.SpawnBot(bot: Player, vehicleId: string, paint: Color3)
	if entries[bot] then
		VehicleService.Despawn(bot)
	end
	local model = VehicleBuilder.Build(vehicleId)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = Config.CollisionGroups.Bots
		end
	end
	VehicleBuilder.ApplyPaint(model, paint)
	local chassis = model.PrimaryPart
	if not chassis then
		model:Destroy()
		return
	end
	local slot = freeSlot()
	model.Name = bot.Name .. "_" .. vehicleId
	model:SetAttribute("OwnerUserId", bot.UserId)
	model:SetAttribute("OwnerName", bot.DisplayName)
	model:SetAttribute("IsBot", true)
	CollectionService:AddTag(model, Config.Tags.Vehicle)
	chassis.Anchored = true
	model:PivotTo(padCFrameForSlot(slot))
	model.Parent = folder
	local entry: VehicleEntry = {
		player = bot,
		model = model,
		chassis = chassis,
		vehicleId = vehicleId,
		slot = slot,
		lastVelocity = Vector3.zero,
		drifting = false,
		boostUntil = 0,
		spinUntil = 0,
		lockedBy = nil,
		lockedUntil = 0,
		crashImmuneUntil = 0,
		speedHistory = {},
		impact = nil,
		lastPosition = chassis.Position,
		strikes = 0,
		isBot = true,
		paint = paint,
	}
	entries[bot] = entry
	applyRelease(entry)
	onSpawned:Fire(bot, entry)
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
	entry.lockedBy = nil
	entry.lockedUntil = 0
	entry.drifting = false
	entry.crashImmuneUntil = workspace:GetServerTimeNow() + Config.Passenger.DamageCooldown
	VehicleService.SetSilhouette(entry.player, false)
end

function VehicleService.RespawnAll()
	for player, entry in entries do
		if entry.isBot then
			VehicleService.SpawnBot(player, entry.vehicleId, entry.paint or Config.Vehicles.Stats[entry.vehicleId].Color)
		else
			VehicleService.Spawn(player)
		end
	end
end

function VehicleService.ResetAllToGrid()
	released = false
	for player, entry in entries do
		if not entry.isBot and DataService.GetSelectedVehicle(player) ~= entry.vehicleId then
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
	for _, group in { Config.CollisionGroups.Vehicles, Config.CollisionGroups.Bots } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
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

	-- Crash watch: horizontal speed lost over the last CrashWindow seconds (one frame is too fragile: replicated
	-- velocity can spread a wall hit across several frames). Jumps and landings are free; walls are not.
	-- Speed sanity: a car that covers more ground per frame than its fastest legal speed allows, several frames
	-- in a row, is put back where it was last seen behaving.
	local sanity = Config.Net.SpeedSanity
	RunService.Heartbeat:Connect(function(dt: number)
		local now = workspace:GetServerTimeNow()
		for player, entry in entries do
			if entry.isBot then
				-- Server-steered: no crash watch (a bot's passenger is hurt by items, not by its own driving) and nothing
				-- to sanity-check.
				entry.lastVelocity = entry.chassis.AssemblyLinearVelocity
				continue
			end
			if entry.chassis.Anchored then
				entry.lastVelocity = Vector3.zero
				table.clear(entry.speedHistory)
				entry.impact = nil
				entry.lastPosition = entry.chassis.Position
				entry.strikes = 0
				continue
			end
			local v = entry.chassis.AssemblyLinearVelocity
			entry.lastVelocity = v
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local history = entry.speedHistory
			table.insert(history, { t = now, speed = speed })
			while history[1] and now - history[1].t > Config.Passenger.CrashWindow do
				table.remove(history, 1)
			end
			local peak = speed
			for _, sample in history do
				peak = math.max(peak, sample.speed)
			end
			local drop = peak - speed
			local boostEnding = now >= entry.boostUntil and now - entry.boostUntil < Config.Passenger.BoostEndGrace
			local impact = entry.impact
			if impact then
				impact.low = math.min(impact.low, speed)
				if now >= impact.settleAt then
					entry.impact = nil
					local lost = math.max(impact.peak - impact.low, impact.bonus)
					if RunService:IsStudio() then
						print(string.format("[VehicleService] crash: %s lost %.0f studs/s", player.Name, lost))
					end
					onCrash:Fire(player, lost)
					table.clear(history)
					table.insert(history, { t = now, speed = speed })
				end
			elseif drop >= Config.Passenger.CrashDeltaThreshold and now >= entry.crashImmuneUntil and now >= entry.spinUntil and not boostEnding then
				entry.impact = { peak = peak, low = speed, settleAt = now + Config.Passenger.CrashSettle, bonus = 0 }
			end

			local pos = entry.chassis.Position
			local stats = Config.Vehicles.Stats[entry.vehicleId] or Config.Vehicles.Stats[Config.Vehicles.Default]
			local legalSpeed = stats.TopSpeed * math.max(Config.Items.LemonNitro.SpeedMult, Config.Chassis.DashSpeedMult) * Config.Chassis.BoostSpeedMult * Config.Chassis.SpeedHardCapMult * Config.PitStop.Cards.SpeedTune.Value * (1 + Config.Upgrades.Speed.Per * Config.Upgrades.Speed.Max)
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
