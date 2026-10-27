--!strict
-- Ambient traffic: Config.Traffic.Count server-owned cars cruising the road grid in right-hand lanes and turning at
-- intersections. They are obstacles, not opponents: player cars collide with them (a hit is a crash like any wall,
-- slipping past one is a near miss), while they ignore the map and each other (collision groups) and follow the
-- ground over bumps. Each car chases a "rabbit" point that moves along its lane at cruise speed, through
-- AlignPosition and AlignOrientation, so clients see smooth physics replication instead of choppy CFrame steps.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local VehicleBuilder = require(ReplicatedStorage.Shared.VehicleBuilder)
local MapService = require(script.Parent.MapService)

local TrafficService = {}

type Car = {
	model: Model,
	body: Part,
	align: AlignPosition,
	orient: AlignOrientation,
	rabbit: Vector3, -- lane point the car chases, at Y = 0; the ground height is added each frame
	dir: Vector3, -- unit vector along X or Z
	speed: number,
	cornerAt: Vector3, -- where the car next changes direction (or clears an intersection going straight)
	nextDir: Vector3,
}

type Exit = { dir: Vector3, weight: number }

local MAX_HOPS = 4 -- corners one car may pass in a single frame
local RAY_UP = 40 -- ground probe starts this far above the car
local RAY_LENGTH = 120

local cars: { Car } = {}
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

local function spawnCar(): boolean
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
		local rabbit = point(rng:NextNumber(low, high), coords[rng:NextInteger(1, #coords)], dir) + rightOf(dir) * cfg.LaneOffset
		if not spotIsFree(rabbit) then
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
			speed = cfg.Speed * (1 + rng:NextNumber(-cfg.SpeedJitter, cfg.SpeedJitter)),
			cornerAt = rabbit,
			nextDir = dir,
		}
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
	groundParams = MapService.StaticRaycastParams()
	for _ = 1, Config.Traffic.Count do
		spawnCar()
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
		local lost = 0
		for i = #cars, 1, -1 do
			local car = cars[i]
			if not car.body:IsDescendantOf(workspace) then
				car.model:Destroy()
				table.remove(cars, i)
				lost += 1
				continue
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
		for _ = 1, lost do
			spawnCar()
		end
	end)
end

return TrafficService
