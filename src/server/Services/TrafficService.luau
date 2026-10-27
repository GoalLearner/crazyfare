--!strict
-- Ambient traffic: Config.Traffic.Count server-owned cars cruising the road grid in right-hand lanes and turning at
-- intersections. They are obstacles, not opponents: player cars collide with them (a hit is a crash like any wall,
-- slipping past one is a near miss), while they ignore the map and each other (collision groups) and follow the
-- ground over bumps. Cars queue behind slower cars in their lane and take turns at intersections (one approach
-- direction at a time), so they never drive through each other. Each car chases a "rabbit" point that moves along
-- its lane at its own speed, through AlignPosition and AlignOrientation, so clients see smooth physics replication
-- instead of choppy CFrame steps.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local VehicleBuilder = require(ReplicatedStorage.Shared.VehicleBuilder)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local PedestrianService = require(script.Parent.PedestrianService)
local PassengerService = require(script.Parent.PassengerService)

local TrafficService = {}

type Car = {
	model: Model,
	body: Part,
	align: AlignPosition,
	orient: AlignOrientation,
	rabbit: Vector3, -- lane point the car chases, at Y = 0; the ground height is added each frame
	dir: Vector3, -- unit vector along X or Z
	cruise: number, -- this car's own speed; no two cars share one
	speed: number, -- current speed (drops behind a slower car)
	cornerAt: Vector3, -- where the car next changes direction (or clears an intersection going straight)
	nextDir: Vector3,
	junction: Vector3?, -- center of the next intersection ahead
	holding: string?, -- key of the intersection this car is allowed through
	holdingCenter: Vector3?,
	blockedFor: number, -- seconds its body has been held up (a player car in the way)
}

type Exit = { dir: Vector3, weight: number }

-- One approach direction holds an intersection at a time; its cars go through single file, everyone else waits.
type Hold = { dir: Vector3, cars: { [Car]: boolean }, count: number }

local MAX_HOPS = 4 -- corners one car may pass in a single frame
local RAY_UP = 40 -- ground probe starts this far above the car
local RAY_LENGTH = 120

local cars: { Car } = {}
local holds: { [string]: Hold } = {}
local crossers: { Vector3 } = {} -- pedestrians and walking-back passengers out in the road this frame
local playerCars: { { position: Vector3, velocity: Vector3 } } = {} -- player cars on the map this frame (flat)
local folder: Folder
local groundParams: RaycastParams
local rng = Random.new()

local function rightOf(dir: Vector3): Vector3
	return Vector3.new(-dir.Z, 0, dir.X)
end

local function along(v: Vector3, dir: Vector3): number
	return if dir.X ~= 0 then v.X else v.Z
end

local function across(v: Vector3, dir: Vector3): number
	return if dir.X ~= 0 then v.Z else v.X
end

local function point(alongValue: number, acrossValue: number, dir: Vector3): Vector3
	return if dir.X ~= 0 then Vector3.new(alongValue, 0, acrossValue) else Vector3.new(acrossValue, 0, alongValue)
end

local function sign(dir: Vector3): number
	return dir.X + dir.Z
end

-- Does the grid have another road beyond `coord` in direction `s` (+1 / -1)?
local function roadBeyond(coords: { number }, coord: number, s: number): boolean
	for _, c in coords do
		if (c - coord) * s > 1 then
			return true
		end
	end
	return false
end

-- Decide what the car does at the next intersection ahead and store the point where that happens.
local function plan(car: Car)
	local cfg = Config.Traffic
	local coords = MapService.GetBlockout().RoadCoords
	local off = cfg.LaneOffset
	local dir = car.dir
	local s = sign(dir)
	local a = along(car.rabbit, dir)
	local roadAcross = across(car.rabbit, dir) - across(rightOf(dir), dir) * off
	local best: number? = nil
	for _, c in coords do
		local ahead = (c - a) * s
		if ahead > off + 1 and (best == nil or ahead < ((best :: number) - a) * s) then
			best = c
		end
	end
	local exits: { Exit } = {}
	if best ~= nil then
		if roadBeyond(coords, best, s) then
			table.insert(exits, { dir = dir, weight = cfg.StraightWeight })
		end
		for _, turn in { rightOf(dir), -rightOf(dir) } do
			if roadBeyond(coords, roadAcross, sign(turn)) then
				table.insert(exits, { dir = turn, weight = cfg.TurnWeight })
			end
		end
	end
	if best == nil or #exits == 0 then
		-- Off the grid's end: turn around where it stands.
		car.nextDir = -dir
		car.cornerAt = car.rabbit
		car.junction = nil
		return
	end
	local total = 0
	for _, exit in exits do
		total += exit.weight
	end
	local pick = rng:NextNumber() * total
	local chosen = exits[#exits].dir
	for _, exit in exits do
		pick -= exit.weight
		if pick <= 0 then
			chosen = exit.dir
			break
		end
	end
	-- The incoming lane meets the outgoing lane before the center on a right turn and past it on a left turn.
	local center = point(best :: number, roadAcross, dir)
	local laneIn = center + rightOf(dir) * off
	car.junction = center
	car.nextDir = chosen
	car.cornerAt = if chosen == dir then laneIn + dir * (off + 1) else laneIn + dir * (off * rightOf(chosen):Dot(dir))
end

local function advance(car: Car, dt: number)
	local remaining = car.speed * dt
	for _ = 1, MAX_HOPS do
		local toCorner = (car.cornerAt - car.rabbit):Dot(car.dir)
		if toCorner > remaining then
			car.rabbit += car.dir * remaining
			return
		end
		remaining -= math.max(toCorner, 0)
		car.rabbit = car.cornerAt
		if car.nextDir == -car.dir then
			car.rabbit -= rightOf(car.dir) * (2 * Config.Traffic.LaneOffset) -- U-turn: hop to the opposite lane
		end
		car.dir = car.nextDir
		plan(car)
	end
end

-- The nearest car ahead in the same lane, and the gap to it.
local function leaderOf(car: Car): (Car?, number)
	local best: Car? = nil
	local bestGap = math.huge
	for _, other in cars do
		if other ~= car and other.dir == car.dir and math.abs(across(other.rabbit - car.rabbit, car.dir)) < 0.5 then
			local gap = (other.rabbit - car.rabbit):Dot(car.dir)
			if gap > 0 and gap < bestGap then
				best = other
				bestGap = gap
			end
		end
	end
	return best, bestGap
end

local function junctionKey(center: Vector3): string
	return string.format("%d:%d", math.round(center.X), math.round(center.Z))
end

local function release(car: Car)
	local key = car.holding
	if not key then
		return
	end
	car.holding = nil
	car.holdingCenter = nil
	local hold = holds[key]
	if hold and hold.cars[car] then
		hold.cars[car] = nil
		hold.count -= 1
		if hold.count <= 0 then
			holds[key] = nil
		end
	end
end

-- May this car go through `center`? Claims it when it is free or held by cars from the same direction.
local function mayEnter(car: Car, center: Vector3): boolean
	local key = junctionKey(center)
	if car.holding == key then
		return true
	end
	local hold = holds[key]
	if hold and hold.dir ~= car.dir then
		return false
	end
	release(car)
	if not hold then
		hold = { dir = car.dir, cars = {}, count = 0 }
		holds[key] = hold
	end
	local claimed = hold :: Hold
	claimed.cars[car] = true
	claimed.count += 1
	car.holding = key
	car.holdingCenter = center
	return true
end

-- Ease toward cruise speed; slow behind a slower car in the lane (down to a stop at a body length), stop at the line
-- when another direction holds the next intersection, and stop short of pedestrians and player cars in the lane.
-- True when a player car is what holds it back.
local function updateSpeed(car: Car, dt: number): boolean
	local cfg = Config.Traffic
	local target = car.cruise
	local leader, gap = leaderOf(car)
	if leader and gap < cfg.FollowGap then
		local room = math.clamp((gap - cfg.BodySize.Z) / (cfg.FollowGap - cfg.BodySize.Z), 0, 1)
		target = math.min(target, leader.speed * room)
	end
	local holdingCenter = car.holdingCenter
	if holdingCenter and (car.rabbit - holdingCenter).Magnitude > cfg.JunctionClear then
		release(car)
	end
	local junction = car.junction
	if junction then
		local toCenter = (junction - car.rabbit):Dot(car.dir)
		if toCenter > 0 and toCenter < cfg.JunctionApproach and not mayEnter(car, junction) then
			target = math.min(target, math.sqrt(2 * cfg.Brake * math.max(toCenter - cfg.StopLine, 0)))
		end
	end
	-- Someone crossing in its lane ahead: stop short of them.
	for _, crosser in crossers do
		local rel = crosser - car.rabbit
		local ahead = rel:Dot(car.dir)
		if ahead > 0 and ahead < cfg.PedestrianStopDistance and math.abs(across(rel, car.dir)) < cfg.PedestrianLaneHalf then
			target = math.min(target, math.sqrt(2 * cfg.Brake * math.max(ahead - cfg.BodySize.Z / 2 - 2, 0)))
		end
	end
	-- A player car in its lane ahead (parked at the curb for a pickup, waiting in a junction, slower in the lane):
	-- brake to stop short of it, or follow it if it is pulling away.
	local heldByPlayer = false
	for _, other in playerCars do
		local rel = other.position - car.rabbit
		local ahead = rel:Dot(car.dir)
		if ahead > 0 and ahead < cfg.PlayerStopDistance and math.abs(across(rel, car.dir)) < cfg.PlayerLaneHalf then
			local pullingAway = math.max(0, other.velocity:Dot(car.dir))
			local allowed = pullingAway + math.sqrt(2 * cfg.Brake * math.max(ahead - cfg.PlayerStopGap, 0))
			if allowed < target then
				target = allowed
				heldByPlayer = true
			end
		end
	end
	if target > car.speed then
		car.speed = math.min(target, car.speed + cfg.Accel * dt)
	else
		car.speed = math.max(target, car.speed - cfg.Brake * dt)
	end
	return heldByPlayer
end

-- A player car touched this traffic car: if they closed fast enough it is a crash, at least a small one.
local function onTouched(car: Car, hit: BasePart)
	local model = hit:FindFirstAncestorOfClass("Model")
	local ownerId = if model then model:GetAttribute("OwnerUserId") else nil
	if typeof(ownerId) ~= "number" then
		return
	end
	local player = Players:GetPlayerByUserId(ownerId)
	local entry = if player then VehicleService.GetEntry(player) else nil
	if not player or not entry or entry.model ~= model then
		return
	end
	local offset = car.body.Position - entry.chassis.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	-- Pre-impact velocities: by the time Touched fires the contact has already stopped the traffic car on the server
	-- (the player car is remote there, so it acts like a wall). Use the traffic car's own driving velocity and the
	-- player car's velocity from the last frame before the hit.
	local rel = entry.lastVelocity - car.dir * car.speed
	local closing = Vector3.new(rel.X, 0, rel.Z):Dot(flat.Unit)
	if closing < Config.Traffic.MinImpactSpeed then
		return
	end
	local stats = Config.Vehicles.Stats[entry.vehicleId] or Config.Vehicles.Stats[Config.Vehicles.Default]
	VehicleService.ReportImpact(player, math.max(closing, Config.Passenger.CrashMinIntensity * stats.TopSpeed))
end

local function targetFor(car: Car): Vector3
	local cfg = Config.Traffic
	local probe = Vector3.new(car.rabbit.X, car.body.Position.Y + RAY_UP, car.rabbit.Z)
	local hit = workspace:Raycast(probe, Vector3.new(0, -RAY_LENGTH, 0), groundParams)
	local groundY = if hit then hit.Position.Y else 0
	return Vector3.new(car.rabbit.X, groundY + cfg.RideHeight + cfg.BodySize.Y / 2, car.rabbit.Z)
end

local function spotIsFree(rabbit: Vector3): boolean
	local cfg = Config.Traffic
	for _, pad in MapService.GetStartPads() do
		if (Vector3.new(pad.position.X, 0, pad.position.Z) - rabbit).Magnitude < cfg.SpawnClearance then
			return false
		end
	end
	for _, car in cars do
		if (car.rabbit - rabbit).Magnitude < cfg.SpawnSpacing then
			return false
		end
	end
	return true
end

local function spawnCar(cruise: number): boolean
	local cfg = Config.Traffic
	local coords = MapService.GetBlockout().RoadCoords
	local low, high = math.huge, -math.huge
	for _, c in coords do
		low = math.min(low, c)
		high = math.max(high, c)
	end
	for _ = 1, cfg.SpawnTries do
		local dir = if rng:NextNumber() < 0.5 then Vector3.xAxis else Vector3.zAxis
		if rng:NextNumber() < 0.5 then
			dir = -dir
		end
		local alongValue = rng:NextNumber(low, high)
		local inJunction = false
		for _, c in coords do
			if math.abs(alongValue - c) < cfg.JunctionClear then
				inJunction = true
			end
		end
		local rabbit = point(alongValue, coords[rng:NextInteger(1, #coords)], dir) + rightOf(dir) * cfg.LaneOffset
		if inJunction or not spotIsFree(rabbit) then
			continue
		end
		local model, body = VehicleBuilder.BuildTraffic(cfg.Colors[rng:NextInteger(1, #cfg.Colors)])
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = Config.CollisionGroups.Traffic
			end
		end
		CollectionService:AddTag(body, Config.Tags.Traffic)
		local attachment = Instance.new("Attachment")
		attachment.Parent = body
		local align = Instance.new("AlignPosition")
		align.Mode = Enum.PositionAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.MaxForce = cfg.MaxForce
		align.Responsiveness = cfg.Responsiveness
		align.Parent = body
		local orient = Instance.new("AlignOrientation")
		orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
		orient.Attachment0 = attachment
		orient.MaxTorque = cfg.MaxForce
		orient.Responsiveness = cfg.Responsiveness
		orient.Parent = body
		local car: Car = {
			model = model,
			body = body,
			align = align,
			orient = orient,
			rabbit = rabbit,
			dir = dir,
			cruise = cruise,
			speed = cruise,
			cornerAt = rabbit,
			nextDir = dir,
			blockedFor = 0,
		}
		body.Touched:Connect(function(hit: BasePart)
			onTouched(car, hit)
		end)
		plan(car)
		model:PivotTo(CFrame.lookAt(rabbit, rabbit + dir))
		local start = targetFor(car)
		model:PivotTo(CFrame.lookAt(start, start + dir))
		align.Position = start
		orient.CFrame = CFrame.lookAt(Vector3.zero, dir)
		model.Parent = folder
		body:SetNetworkOwner(nil)
		table.insert(cars, car)
		return true
	end
	return false
end

local function spawnAll()
	for _, car in cars do
		car.model:Destroy()
	end
	table.clear(cars)
	table.clear(holds)
	groundParams = MapService.StaticRaycastParams()
	-- One cruise speed per slice of SpeedMin..SpeedMax, shuffled, so every car runs at its own speed.
	local cfg = Config.Traffic
	local speeds: { number } = {}
	for i = 1, cfg.Count do
		table.insert(speeds, cfg.SpeedMin + (cfg.SpeedMax - cfg.SpeedMin) * ((i - 1) + rng:NextNumber()) / cfg.Count)
	end
	for i = #speeds, 2, -1 do
		local j = rng:NextInteger(1, i)
		speeds[i], speeds[j] = speeds[j], speeds[i]
	end
	for _, cruise in speeds do
		spawnCar(cruise)
	end
end

function TrafficService.Init()
	local groups = Config.CollisionGroups
	if not PhysicsService:IsCollisionGroupRegistered(groups.Traffic) then
		PhysicsService:RegisterCollisionGroup(groups.Traffic)
	end
	PhysicsService:CollisionGroupSetCollidable(groups.Traffic, groups.Traffic, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Traffic, groups.Default, false)
	folder = MapService.GetRuntimeFolder("Traffic")
	MapService.OnMapLoaded:Connect(spawnAll)
end

function TrafficService.Start()
	spawnAll()
	RunService.Heartbeat:Connect(function(dt: number)
		crossers = PedestrianService.GetCrossers()
		for _, walker in PassengerService.GetWalkersInRoad() do
			table.insert(crossers, walker)
		end
		table.clear(playerCars)
		for _, entry in VehicleService.GetAll() do
			local chassis = entry.chassis
			if not chassis.Anchored then
				local p, v = chassis.Position, chassis.AssemblyLinearVelocity
				table.insert(playerCars, { position = Vector3.new(p.X, 0, p.Z), velocity = Vector3.new(v.X, 0, v.Z) })
			end
		end
		local lost: { number } = {}
		for i = #cars, 1, -1 do
			local car = cars[i]
			if not car.body:IsDescendantOf(workspace) then
				release(car)
				car.model:Destroy()
				table.remove(cars, i)
				table.insert(lost, car.cruise)
				continue
			end
			local heldByPlayer = updateSpeed(car, dt)
			-- Held up by a player car (stopped for one, or its body pushed back by one): wait, so the cars queued behind
			-- wait too; after a while, respawn elsewhere.
			local lag = (car.rabbit - Vector3.new(car.body.Position.X, 0, car.body.Position.Z)):Dot(car.dir)
			local pushedBack = lag > Config.Traffic.BlockedLag
			if pushedBack then
				car.speed = 0
			end
			if pushedBack or (heldByPlayer and car.speed < 1) then
				car.blockedFor += dt
				if car.blockedFor > Config.Traffic.BlockedRespawn then
					release(car)
					car.model:Destroy()
					table.remove(cars, i)
					table.insert(lost, car.cruise)
					continue
				end
			else
				car.blockedFor = 0
			end
			advance(car, dt)
			local target = targetFor(car)
			if (car.body.Position - target).Magnitude > Config.Traffic.ResetDistance then
				car.body.AssemblyLinearVelocity = Vector3.zero
				car.model:PivotTo(CFrame.lookAt(target, target + car.dir))
			end
			car.align.Position = target
			car.orient.CFrame = CFrame.lookAt(Vector3.zero, car.dir)
		end
		for _, cruise in lost do
			spawnCar(cruise)
		end
	end)
end

return TrafficService
