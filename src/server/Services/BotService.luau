--!strict
-- AI rival taxis. With too few people they fill the match to Config.Bots.FillTo drivers, and give their seats up as real
-- players join (Rebalance runs at every round setup). A bot is a Racers stand-in with a real VehicleService entry, so
-- the normal rules apply: it claims a passenger by stopping next to them, delivers by stopping at the drop-off, holds and
-- uses items, gets hit, and shows up in the standings. This service only drives and decides.
--
-- Driving: server physics like traffic. Each bot chases a "rabbit" point along a route over the road grid (the center
-- line, nudged right when another bot comes the other way), slowing for corners, for cars and people in the road ahead
-- and for crossing traffic at junctions, then pulls over next to its passenger or drop-off and stops.
-- Brain: go for the passenger worth the most per second of driving (Golden Fares above all), think again when they're
-- taken, deliver, repeat; use items when there's a reason to. Every number is Config.Bots.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Racers = require(script.Parent.Parent.Racers)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local ComboService = require(script.Parent.ComboService)
local PassengerService = require(script.Parent.PassengerService)
local FareService = require(script.Parent.FareService)
local ItemService = require(script.Parent.ItemService)
local PedestrianService = require(script.Parent.PedestrianService)
local TrafficService = require(script.Parent.TrafficService)

local BotService = {}

type Bot = {
	driver: Player,
	slot: number,
	skill: number,
	model: Model?, -- the car the movers below are on (a respawned car gets new ones)
	align: AlignPosition?,
	orient: AlignOrientation?,
	rabbit: Vector3, -- the point it chases, flat (Y = 0)
	dir: Vector3, -- flat unit heading
	speed: number,
	route: { Vector3 }, -- flat waypoints still ahead; the last one is where it stops
	goal: string, -- "none" | "pickup" | "dropoff"
	npcId: number?,
	restUntil: number, -- os.clock(): no new passenger before this (a breather after each fare)
	thinkAt: number,
	stoppedSince: number?, -- os.clock() when it came to rest at the end of its route
	lateral: number, -- sideways offset from the route (right-hand positive), for passing other bots
	stuckFor: number,
	spinAngle: number,
	wasAnchored: boolean,
	heldItem: string,
	heldSince: number,
	staged: { mode: string, dir: Vector3, speed: number, untilClock: number }?, -- Studio debug: parked or charging
	dropTo: Vector3?, -- the drop-off its route leads to (a carpool's next stop moves it)
	airY: number, -- thrown into the air (a hydrant): height above the ride height...
	airVel: number, -- ...and its vertical speed
}

local bots: { [Player]: Bot } = {}
local order: { Player } = {} -- oldest first; the newest leaves first
local rng = Random.new()
local groundParams: RaycastParams? = nil
local blockers: { { position: Vector3, velocity: Vector3, clearance: number } } = {} -- world-event obstacles

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rightOf(dir: Vector3): Vector3
	return Vector3.new(-dir.Z, 0, dir.X)
end

-- ---------------------------------------------------------------- the road grid

local function roadCoords(): ({ number }, number, number)
	local coords = table.clone(MapService.GetBlockout().RoadCoords)
	table.sort(coords)
	return coords, coords[1], coords[#coords]
end

-- The road line nearest a point: axis "x" is a road running along Z at X = coord; "z" runs along X at Z = coord.
local function nearestRoad(p: Vector3): (string, number, number)
	local coords = roadCoords()
	local bestAxis, bestCoord, bestDist = "x", coords[1], math.huge
	for _, c in coords do
		local dx = math.abs(p.X - c)
		if dx < bestDist then
			bestAxis, bestCoord, bestDist = "x", c, dx
		end
		local dz = math.abs(p.Z - c)
		if dz < bestDist then
			bestAxis, bestCoord, bestDist = "z", c, dz
		end
	end
	return bestAxis, bestCoord, bestDist
end

local function project(axis: string, coord: number, p: Vector3): Vector3
	local _, lo, hi = roadCoords()
	if axis == "x" then
		return Vector3.new(coord, 0, math.clamp(p.Z, lo, hi))
	end
	return Vector3.new(math.clamp(p.X, lo, hi), 0, coord)
end

-- Shortest drive over the grid from `from` to `to`: center-line waypoints, ending where `to` meets its road.
local function plan(from: Vector3, to: Vector3): { Vector3 }
	local coords = roadCoords()
	local fa, fc = nearestRoad(from)
	local ta, tc = nearestRoad(to)
	local s = project(fa, fc, from)
	local t = project(ta, tc, to)
	if fa == ta and fc == tc then
		return { s, t }
	end
	-- Nodes: every junction, plus the start and end points on their roads.
	local nodes: { Vector3 } = {}
	for _, x in coords do
		for _, z in coords do
			table.insert(nodes, Vector3.new(x, 0, z))
		end
	end
	table.insert(nodes, s)
	local sIndex = #nodes
	table.insert(nodes, t)
	local tIndex = #nodes
	-- Edges: neighbours along each road line.
	local edges: { { number } } = {}
	for i = 1, #nodes do
		edges[i] = {}
	end
	local function link(axis: string, coord: number)
		local onLine: { number } = {}
		for i, p in nodes do
			local value = if axis == "x" then p.X else p.Z
			local isEnd = (i == sIndex and fa == axis and fc == coord) or (i == tIndex and ta == axis and tc == coord)
			local isJunction = i ~= sIndex and i ~= tIndex and math.abs(value - coord) < 0.01
			if isEnd or isJunction then
				table.insert(onLine, i)
			end
		end
		table.sort(onLine, function(a, b)
			local pa, pb = nodes[a], nodes[b]
			return if axis == "x" then pa.Z < pb.Z else pa.X < pb.X
		end)
		for k = 1, #onLine - 1 do
			table.insert(edges[onLine[k]], onLine[k + 1])
			table.insert(edges[onLine[k + 1]], onLine[k])
		end
	end
	for _, c in coords do
		link("x", c)
		link("z", c)
	end
	-- Dijkstra (under 40 nodes).
	local dist: { number } = {}
	local prev: { number } = {}
	local done: { boolean } = {}
	for i = 1, #nodes do
		dist[i] = math.huge
		prev[i] = 0
		done[i] = false
	end
	dist[sIndex] = 0
	for _ = 1, #nodes do
		local u, best = 0, math.huge
		for i = 1, #nodes do
			if not done[i] and dist[i] < best then
				u, best = i, dist[i]
			end
		end
		if u == 0 or u == tIndex then
			break
		end
		done[u] = true
		for _, v in edges[u] do
			local d = best + (nodes[u] - nodes[v]).Magnitude
			if d < dist[v] then
				dist[v] = d
				prev[v] = u
			end
		end
	end
	if dist[tIndex] == math.huge then
		return { s, t }
	end
	local path: { Vector3 } = {}
	local at = tIndex
	while at ~= 0 do
		table.insert(path, 1, nodes[at])
		at = prev[at]
	end
	return path
end

-- A route from where the bot is to a curb spot beside `target` (a passenger or a drop-off).
local function setRoute(bot: Bot, target: Vector3)
	local cfg = Config.Bots
	local route = plan(bot.rabbit, target)
	local axis, coord, perp = nearestRoad(target)
	local offset = math.clamp(perp - cfg.StopReach, 0, cfg.MaxCurbOffset)
	if offset > 0.5 then
		local side = if axis == "x" then Vector3.new(math.sign(target.X - coord), 0, 0) else Vector3.new(0, 0, math.sign(target.Z - coord))
		table.insert(route, route[#route] + side * offset)
	end
	bot.route = route
	bot.stoppedSince = nil
end

local function remaining(bot: Bot): number
	local total, at = 0, bot.rabbit
	for _, p in bot.route do
		total += (p - at).Magnitude
		at = p
	end
	return total
end

-- ---------------------------------------------------------------- the brain

local function targetedByOthers(bot: Bot, npcId: number): boolean
	for _, other in bots do
		if other ~= bot and other.goal == "pickup" and other.npcId == npcId then
			return true
		end
	end
	return false
end

-- One of the few passengers worth the most per second of driving to them (better ones likelier).
local function pickPassenger(bot: Bot): PassengerService.Npc?
	local cfg = Config.Bots
	local cruise = cfg.CruiseSpeed * bot.skill
	local ranked: { { npc: PassengerService.Npc, score: number } } = {}
	for _, npc in PassengerService.GetAll() do
		if npc.state ~= 0 or (not npc.golden and targetedByOthers(bot, npc.id)) then
			continue
		end
		local tier = Config.Fares.Tiers[npc.tier]
		local ticking = Config.Chaos.Ticking
		local value = (if tier then tier.Base else 1) ^ cfg.Greed
			* (if npc.golden then Config.Golden.PayMult * cfg.GoldenBias elseif npc.ticking then (ticking.StartMult + ticking.FloorMult) / 2 else 1)
		local eta = (flat(npc.position) - bot.rabbit).Magnitude * cfg.RouteFactor / cruise + cfg.PickupOverhead
		table.insert(ranked, { npc = npc, score = value / eta * rng:NextNumber(1 - cfg.Jitter, 1 + cfg.Jitter) })
	end
	if #ranked == 0 then
		return nil
	end
	table.sort(ranked, function(a, b)
		return a.score > b.score
	end)
	local total = 0
	for i = 1, math.min(cfg.Choices, #ranked) do
		total += ranked[i].score
	end
	local roll = rng:NextNumber() * total
	for i = 1, math.min(cfg.Choices, #ranked) do
		roll -= ranked[i].score
		if roll <= 0 then
			return ranked[i].npc
		end
	end
	return ranked[1].npc
end

local function rivalNear(bot: Bot, range: number, wantLoaded: boolean, behind: boolean): boolean
	for other, entry in VehicleService.GetAll() do
		if other == bot.driver or entry.chassis.Anchored then
			continue
		end
		local rel = flat(entry.chassis.Position) - bot.rabbit
		if rel.Magnitude > range then
			continue
		end
		if behind and rel:Dot(bot.dir) > 0 then
			continue
		end
		if not wantLoaded or PassengerService.GetLoaded(other) then
			return true
		end
	end
	return false
end

local function useItems(bot: Bot, now: number)
	local cfg = Config.Bots
	local item = ItemService.GetHeld(bot.driver)
	if item == "" then
		bot.heldItem = ""
		return
	end
	if item ~= bot.heldItem then
		bot.heldItem = item
		bot.heldSince = now
	end
	local loaded = FareService.GetFare(bot.driver) ~= nil
	local reason = false
	if item == "Tomato" then
		reason = not loaded and rivalNear(bot, Config.Items.Tomato.LockRange, true, false) -- throwing while loaded costs its own passenger HP
	elseif item == "Banana" or item == "OilSlick" then
		reason = rivalNear(bot, cfg.TrapBehind, false, true) or now - bot.heldSince > cfg.ItemHoldMax
	elseif item == "LemonNitro" then
		reason = #bot.route > 0 and (bot.route[1] - bot.rabbit).Magnitude > cfg.NitroStraight
	elseif item == "Shield" or item == "Seatbelt" then
		reason = loaded
	end
	if reason and rng:NextNumber() < cfg.ItemUseChance then
		ItemService.Use(bot.driver)
	end
end

local function think(bot: Bot, now: number)
	local cfg = Config.Bots
	useItems(bot, now)
	local fare = FareService.GetFare(bot.driver)
	if fare then
		if bot.goal ~= "dropoff" or bot.dropTo ~= fare.destination then
			bot.goal = "dropoff"
			bot.npcId = nil
			bot.dropTo = fare.destination
			setRoute(bot, fare.destination)
		elseif #bot.route == 0 and bot.stoppedSince and os.clock() - bot.stoppedSince > cfg.ClaimWait then
			setRoute(bot, fare.destination) -- pulled up short somehow: go again
		end
		return
	end
	if bot.goal == "dropoff" then
		-- the fare just ended (delivered, bailed, timed out): a breather before the next one
		bot.goal = "none"
		bot.route = {}
		bot.restUntil = os.clock() + rng:NextNumber(cfg.RestMin, cfg.RestMax)
	end
	if os.clock() < bot.restUntil then
		return
	end
	if bot.goal == "pickup" and bot.npcId then
		local npc = PassengerService.Get(bot.npcId)
		local waitedOut = bot.stoppedSince ~= nil and os.clock() - bot.stoppedSince > cfg.ClaimWait
		if npc and npc.state == 0 and not waitedOut then
			return -- still going for them
		end
	end
	local target = pickPassenger(bot)
	if target then
		bot.goal = "pickup"
		bot.npcId = target.id
		setRoute(bot, target.position)
	else
		bot.goal = "none"
		bot.npcId = nil
		bot.route = {}
	end
end

-- ---------------------------------------------------------------- driving

-- Movers on the bot's car (made again when the car is respawned).
local function attachMovers(bot: Bot, entry: VehicleService.VehicleEntry)
	local cfg = Config.Bots
	local chassis = entry.chassis
	local attachment = Instance.new("Attachment")
	attachment.Name = "BotMover"
	attachment.Parent = chassis
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxForce = cfg.MaxForce
	align.Responsiveness = cfg.Responsiveness
	align.Position = chassis.Position
	align.Parent = chassis
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = attachment
	orient.MaxTorque = cfg.MaxForce
	orient.Responsiveness = cfg.Responsiveness
	orient.CFrame = chassis.CFrame.Rotation
	orient.Parent = chassis
	bot.model = entry.model
	bot.align = align
	bot.orient = orient
end

local function groundY(at: Vector3, fromY: number): number
	local params = groundParams
	if not params then
		params = MapService.StaticRaycastParams()
		groundParams = params
	end
	-- From just above the car, so lamp arms and signs over the road never read as ground (ramps still do).
	local hit = workspace:Raycast(Vector3.new(at.X, fromY + 6, at.Z), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position.Y else 0
end

-- The next junction ahead on the current road, and how far away it is.
local function junctionAhead(bot: Bot): (Vector3?, number)
	local coords = roadCoords()
	local p, d = bot.rabbit, bot.dir
	local along = if math.abs(d.X) > math.abs(d.Z) then "x" else "z"
	local best: Vector3? = nil
	local bestDist = math.huge
	for _, c in coords do
		local ahead = if along == "x" then (c - p.X) * math.sign(d.X) else (c - p.Z) * math.sign(d.Z)
		if ahead > -Config.Bots.JunctionBox and ahead < bestDist then
			best = if along == "x" then Vector3.new(c, 0, p.Z) else Vector3.new(p.X, 0, c)
			bestDist = ahead
		end
	end
	return best, bestDist
end

-- How fast the bot may go right now: cruise, corners, the stop at the end, things in the road, crossing traffic.
local function allowedSpeed(bot: Bot, entry: VehicleService.VehicleEntry, now: number, traffic: { { position: Vector3, dir: Vector3, speed: number, halfLength: number } }, crossers: { Vector3 }): number
	local cfg = Config.Bots
	local brake = cfg.Brake
	local boost = if now < entry.boostUntil then Config.Items.LemonNitro.SpeedMult else 1
	local limit = cfg.CruiseSpeed * bot.skill * boost
	if #bot.route == 0 then
		return 0
	end
	-- the stop at the end of the route
	limit = math.min(limit, math.sqrt(2 * brake * remaining(bot)))
	-- a corner at the next waypoint
	local nextPoint, afterPoint = bot.route[1], bot.route[2]
	if afterPoint then
		local turn = (afterPoint - nextPoint)
		if turn.Magnitude > 0.01 and turn.Unit:Dot(bot.dir) < 0.85 then
			local d = (nextPoint - bot.rabbit).Magnitude
			limit = math.min(limit, math.sqrt(cfg.CornerSpeed * cfg.CornerSpeed + 2 * brake * d))
		end
	end
	-- cars (players, other bots) and people in the road ahead, measured from the line the bot is actually on (so two
	-- bots keeping right to pass don't see each other as in the way)
	local lane = bot.rabbit + rightOf(bot.dir) * bot.lateral
	local function obstacle(position: Vector3, alongSpeed: number, clearance: number)
		local rel = flat(position) - lane
		local ahead = rel:Dot(bot.dir)
		if ahead <= 0 or ahead > cfg.FollowDistance then
			return
		end
		local side = (rel - bot.dir * ahead).Magnitude
		if side < clearance then
			limit = math.min(limit, math.max(0, alongSpeed) + math.sqrt(2 * brake * math.max(ahead - cfg.FollowGap, 0)))
		end
	end
	for other, otherEntry in VehicleService.GetAll() do
		if other ~= bot.driver then
			local v = otherEntry.chassis.AssemblyLinearVelocity
			obstacle(otherEntry.chassis.Position, flat(v):Dot(bot.dir), cfg.CarClearance)
		end
	end
	for _, person in crossers do
		obstacle(person, 0, cfg.PersonClearance)
	end
	for _, blocker in blockers do
		obstacle(blocker.position, flat(blocker.velocity):Dot(bot.dir), blocker.clearance)
	end
	-- crossing traffic inside the next junction: wait for it
	local junction, toJunction = junctionAhead(bot)
	if junction and toJunction > 0 and toJunction < cfg.JunctionLook then
		for _, car in traffic do
			local rel = flat(car.position) - junction
			local box = cfg.JunctionBox + car.halfLength
			if math.abs(rel.X) < box and math.abs(rel.Z) < box and car.speed > 2 and math.abs(car.dir:Dot(bot.dir)) < 0.5 then
				limit = math.min(limit, math.sqrt(2 * brake * math.max(toJunction - cfg.JunctionBox - 2, 0)))
				break
			end
		end
	end
	return limit
end

-- Another bot coming the other way on the same road: both keep right.
local function wantedLateral(bot: Bot): number
	local cfg = Config.Bots
	for other, otherBot in bots do
		if other ~= bot.driver then
			local rel = otherBot.rabbit - bot.rabbit
			local ahead = rel:Dot(bot.dir)
			if ahead > 0 and ahead < cfg.PassLook and otherBot.dir:Dot(bot.dir) < -0.7 and (rel - bot.dir * ahead).Magnitude < cfg.CarClearance * 1.5 then
				return cfg.PassShift
			end
		end
	end
	-- An empty item slot: hug the curb past a fruit stand ahead on this road (it smashes into a free item).
	if ItemService.GetHeld(bot.driver) == "" then
		local fruit = Config.Chaos.FruitStands
		for _, stand in ItemService.GetActiveStands() do
			local rel = flat(stand.Position) - bot.rabbit
			local ahead = rel:Dot(bot.dir)
			local side = rel:Dot(rightOf(bot.dir))
			if ahead > 0 and ahead < fruit.BotLook and math.abs(side) <= fruit.BotReach then
				return math.clamp(side, -cfg.MaxCurbOffset, cfg.MaxCurbOffset)
			end
		end
	end
	return 0
end

local function advance(bot: Bot, distance: number)
	local left = distance
	while left > 0 and #bot.route > 0 do
		local to = bot.route[1] - bot.rabbit
		local d = to.Magnitude
		if d > 0.01 then
			bot.dir = to.Unit
		end
		if d <= left then
			bot.rabbit = bot.route[1]
			table.remove(bot.route, 1)
			left -= d
		else
			bot.rabbit += to.Unit * left
			left = 0
		end
	end
end

local function drive(bot: Bot, entry: VehicleService.VehicleEntry, dt: number, now: number, traffic: { { position: Vector3, dir: Vector3, speed: number, halfLength: number } }, crossers: { Vector3 })
	local cfg = Config.Bots
	local chassis = entry.chassis
	local align, orient = bot.align, bot.orient
	if not align or not orient then
		return
	end
	if chassis.Anchored then
		-- Parked on the grid (between rounds): start fresh from here when released.
		bot.wasAnchored = true
		bot.rabbit = flat(chassis.Position)
		bot.dir = flat(chassis.CFrame.LookVector).Unit
		bot.speed = 0
		bot.route = {}
		bot.goal = "none"
		bot.npcId = nil
		align.Position = chassis.Position
		orient.CFrame = chassis.CFrame.Rotation
		return
	end
	if bot.wasAnchored then
		bot.wasAnchored = false
		bot.thinkAt = 0
	end

	-- Studio debug: parked broadside, or charging in a straight line
	local staged = bot.staged
	if staged then
		if os.clock() < staged.untilClock then
			bot.speed = staged.speed
			bot.rabbit += staged.dir * staged.speed * dt
			align.Position = Vector3.new(bot.rabbit.X, groundY(bot.rabbit, chassis.Position.Y) + cfg.RideHeight, bot.rabbit.Z)
			orient.CFrame = CFrame.lookAt(Vector3.zero, staged.dir)
			return
		end
		bot.staged = nil
		bot.route = {}
		bot.thinkAt = 0
	end

	-- Spinout from a Banana: stop and spin in place.
	if now < entry.spinUntil then
		bot.speed = math.max(0, bot.speed - cfg.Brake * 2 * dt)
		bot.spinAngle += cfg.SpinRate * dt
		align.Position = Vector3.new(bot.rabbit.X, groundY(bot.rabbit, chassis.Position.Y) + cfg.RideHeight, bot.rabbit.Z)
		orient.CFrame = CFrame.lookAt(Vector3.zero, bot.dir) * CFrame.Angles(0, bot.spinAngle, 0)
		return
	end
	bot.spinAngle = 0

	local target = allowedSpeed(bot, entry, now, traffic, crossers)
	if target > bot.speed then
		bot.speed = math.min(target, bot.speed + cfg.Accel * dt)
	else
		bot.speed = math.max(target, bot.speed - cfg.Brake * dt)
	end

	-- Held up (a car parked in its way, a wall it got shoved into): the target waits; too long and it's put back.
	local lateralGoal = if remaining(bot) > 25 then wantedLateral(bot) else 0
	bot.lateral += (lateralGoal - bot.lateral) * math.clamp(dt * 4, 0, 1)
	local wanted = bot.rabbit + rightOf(bot.dir) * bot.lateral
	local lag = (wanted - flat(chassis.Position)).Magnitude
	if lag > cfg.StuckLag then
		bot.stuckFor += dt
		if bot.stuckFor > cfg.StuckSeconds then
			bot.stuckFor = 0
			local y = groundY(wanted, chassis.Position.Y) + cfg.RideHeight
			VehicleService.Teleport(entry, CFrame.lookAt(Vector3.new(wanted.X, y, wanted.Z), Vector3.new(wanted.X, y, wanted.Z) + bot.dir))
		end
	else
		bot.stuckFor = 0
		advance(bot, bot.speed * dt)
	end

	if #bot.route == 0 and bot.speed < 1 then
		bot.stoppedSince = bot.stoppedSince or os.clock()
	end
	-- thrown into the air: an arc on top of the ride height, as floaty as the players' air
	if bot.airY > 0 or bot.airVel > 0 then
		bot.airVel -= workspace.Gravity * Config.Chassis.AirGravityMult * dt
		bot.airY = math.max(0, bot.airY + bot.airVel * dt)
		if bot.airY <= 0 then
			bot.airVel = 0
		end
	end
	wanted = bot.rabbit + rightOf(bot.dir) * bot.lateral
	align.Position = Vector3.new(wanted.X, groundY(wanted, chassis.Position.Y) + cfg.RideHeight + bot.airY, wanted.Z)
	orient.CFrame = CFrame.lookAt(Vector3.zero, bot.dir)
end

local function step(dt: number)
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local traffic = TrafficService.GetCars()
	local crossers = PedestrianService.GetCrossers()
	for _, walker in PassengerService.GetWalkersInRoad() do
		table.insert(crossers, walker)
	end
	for driver, bot in bots do
		local entry = VehicleService.GetEntry(driver)
		if not entry then
			continue
		end
		if entry.model ~= bot.model then
			attachMovers(bot, entry)
		end
		if not entry.chassis.Anchored and clock >= bot.thinkAt then
			bot.thinkAt = clock + Config.Bots.ThinkSeconds / bot.skill
			think(bot, now)
		end
		drive(bot, entry, dt, now, traffic, crossers)
	end
end

-- ---------------------------------------------------------------- joining and leaving

local function addBot()
	local cfg = Config.Bots
	local used: { [number]: boolean } = {}
	for _, bot in bots do
		used[bot.slot] = true
	end
	local slot = 1
	while used[slot] do
		slot += 1
	end
	local name = cfg.Names[(slot - 1) % #cfg.Names + 1]
	local driver = Racers.NewBot(slot, name)
	local bot: Bot = {
		driver = driver,
		slot = slot,
		skill = cfg.Skills[(slot - 1) % #cfg.Skills + 1],
		model = nil,
		align = nil,
		orient = nil,
		rabbit = Vector3.zero,
		dir = Vector3.new(0, 0, -1),
		speed = 0,
		route = {},
		goal = "none",
		npcId = nil,
		restUntil = 0,
		thinkAt = 0,
		stoppedSince = nil,
		lateral = 0,
		stuckFor = 0,
		spinAngle = 0,
		wasAnchored = true,
		heldItem = "",
		heldSince = 0,
		staged = nil,
		dropTo = nil,
		airY = 0,
		airVel = 0,
	}
	bots[driver] = bot
	table.insert(order, driver)
	VehicleService.SpawnBot(driver, cfg.VehicleId, cfg.Colors[(slot - 1) % #cfg.Colors + 1])
end

local function removeBot(driver: Player)
	PassengerService.Release(driver)
	ComboService.Remove(driver)
	ItemService.Forget(driver)
	FareService.RemoveRacer(driver)
	VehicleService.Despawn(driver)
	Racers.RemoveBot(driver)
	bots[driver] = nil
	local index = table.find(order, driver)
	if index then
		table.remove(order, index)
	end
end

-- Bots fill the match to FillTo drivers while at least MinHumans people are here; the newest leaves first.
-- Studio: the first bot is put 40 studs ahead of this driver's car, either parked broadside with a passenger aboard
-- ("park": ram it) or charging straight back at the car ("charge": get rammed).
function BotService.DebugStage(player: Player, mode: string)
	local entry = VehicleService.GetEntry(player)
	local driver = order[1]
	local bot = if driver then bots[driver] else nil
	local botEntry = if driver then VehicleService.GetEntry(driver) else nil
	if not RunService:IsStudio() or not entry or not bot or not botEntry or not driver then
		return
	end
	local cfg = Config.Bots
	local look = flat(entry.chassis.CFrame.LookVector)
	look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
	local at = flat(entry.chassis.Position) + look * 40
	local dir = if mode == "charge" then -look else rightOf(look)
	local y = groundY(at, entry.chassis.Position.Y) + cfg.RideHeight
	bot.rabbit = at
	bot.dir = dir
	bot.staged = { mode = mode, dir = dir, speed = if mode == "charge" then cfg.DebugChargeSpeed else 0, untilClock = os.clock() + cfg.DebugStageSeconds }
	VehicleService.Teleport(botEntry, CFrame.lookAt(Vector3.new(at.X, y, at.Z), Vector3.new(at.X, y, at.Z) + dir))
	if mode == "park" then
		FareService.DebugClaimNearest(driver)
	end
	print(string.format("[BotService] %s staged 40 studs ahead of %s (%s)", driver.Name, player.Name, mode))
end

-- World-event obstacles in the road (the parade, the money truck): bots slow and stop for them like for a car.
function BotService.SetBlockers(list: { { position: Vector3, velocity: Vector3, clearance: number } })
	blockers = list
end

-- Throw a bot's car into the air at `speed` studs/s (a hydrant).
function BotService.Launch(driver: Player, speed: number)
	local bot = bots[driver]
	if bot then
		bot.airVel = math.max(bot.airVel, speed)
		bot.airY = math.max(bot.airY, 0.01)
	end
end

function BotService.Rebalance()
	local cfg = Config.Bots
	local humans = #Players:GetPlayers()
	local want = if cfg.Enabled and humans >= cfg.MinHumans then math.max(0, cfg.FillTo - humans) else 0
	while #order > want do
		removeBot(order[#order])
	end
	while #order < want do
		addBot()
	end
end

function BotService.RemoveAll()
	while #order > 0 do
		removeBot(order[#order])
	end
end

function BotService.Count(): number
	return #order
end

function BotService.Init()
	local groups = Config.CollisionGroups
	local PhysicsService = game:GetService("PhysicsService")
	-- Bots bump player cars and each other; they float over the map at ride height and ghost through traffic
	-- (traffic queues for them like any car in its lane).
	PhysicsService:CollisionGroupSetCollidable(groups.Bots, groups.Traffic, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Bots, groups.Default, false)
	MapService.OnMapLoaded:Connect(function()
		groundParams = nil
	end)
end

function BotService.Start()
	RunService.Heartbeat:Connect(step)
end

return BotService
