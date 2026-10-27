--!strict
-- Pedestrians: Config.Pedestrians.Count walkers going around the sidewalk ring of each block and crossing the street at
-- the corners. Before stepping off the curb they look for cars (players and traffic) heading for the crosswalk and wait
-- for a gap; mid-crossing they run if a car bears down on them. Traffic stops for anyone crossing in its lane
-- (TrafficService reads GetCrossers). A racer's car (player or bot) bearing down on one gets a cartoon dive-roll out
-- of its path most of the time (Config.Pedestrians.DiveChance, less at top speed). A failed dive is a clip: the
-- passenger takes PassengerDamage (Shield, Seatbelt and armor count), the combo ends, and when a rival's Banana or Oil
-- Slick had the car out of control the damage, and any bail, is theirs. The walker only rolls, hops, spins and yells:
-- no knockdown, no injury (Roblox "mild violence"). Walkers are anchored, non-colliding figures moved by CFrame, like
-- the bailing passengers.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local PassengerService = require(script.Parent.PassengerService)
local ItemService = require(script.Parent.ItemService)
local ComboService = require(script.Parent.ComboService)

local PedestrianService = {}

type Leg = {
	to: Vector3, -- flat waypoint (Y = 0)
	cx: number, -- block the walker is on when it arrives
	cz: number,
	sx: number, -- which corner of that block (signs)
	sz: number,
	crossing: boolean,
}

type Ped = {
	model: Model,
	torso: Part,
	bubble: TextLabel,
	pos: Vector3, -- feet on the ground plan (Y = 0)
	leg: Leg,
	at: Leg, -- the corner the current leg started from (its block and signs)
	from: Vector3, -- corner the current leg started at
	waiting: number, -- seconds at the curb on a crossing leg
	started: boolean, -- has stepped off the curb (crossing legs)
	phase: number, -- walk bob
	hopStart: number,
	immuneUntil: number,
	bubbleUntil: number,
	diveStart: number, -- the dive-roll out of a car's path
	diveFrom: Vector3,
	diveTo: Vector3,
	decidedUntil: number, -- rolled for the car coming at them; no second roll before this
	forced: string?, -- Studio debug: "dive" or "clip" for the next approach
	standUntil: number, -- Studio debug: stands where it was put until then
}

-- Figure proportions (match the passengers).
local TORSO_SIZE = Vector3.new(1.6, 1.8, 0.9)
local HEAD_SIZE = Vector3.new(1.1, 1.1, 1.1)
local LEG_SIZE = Vector3.new(0.7, 1.6, 0.7)
local ARM_SIZE = Vector3.new(0.5, 1.5, 0.5)
local TORSO_HEIGHT = 2.5 -- torso center above the ground
local DEBUG_STAND_SECONDS = 5 -- a walker the Debug panel put on the road waits there this long
local BOB = 0.25
local RAY_UP = 30
local RAY_LENGTH = 80

local peds: { Ped } = {}
local folder: Folder
local groundParams: RaycastParams
local rng = Random.new()

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function ringRadius(): number
	local B = MapService.GetBlockout()
	return B.CellSize / 2 - Config.Pedestrians.RingInset
end

local function cellSpacing(): number
	local centers = MapService.GetBlockout().CellCenters
	return math.abs(centers[2] - centers[1])
end

local function isPlaza(cx: number, cz: number): boolean
	return math.abs(cx) < 1 and math.abs(cz) < 1
end

local function cellExists(cx: number, cz: number): boolean
	local hasX, hasZ = false, false
	for _, c in MapService.GetBlockout().CellCenters do
		if math.abs(c - cx) < 1 then
			hasX = true
		end
		if math.abs(c - cz) < 1 then
			hasZ = true
		end
	end
	return hasX and hasZ and not isPlaza(cx, cz)
end

local function corner(cx: number, cz: number, sx: number, sz: number): Vector3
	local r = ringRadius()
	return Vector3.new(cx + sx * r, 0, cz + sz * r)
end

-- Legs out of a corner: two along the block, and a crossing on each side that has a block across the street.
local function options(leg: Leg): { Leg }
	local cx, cz, sx, sz = leg.cx, leg.cz, leg.sx, leg.sz
	local list: { Leg } = {
		{ to = corner(cx, cz, -sx, sz), cx = cx, cz = cz, sx = -sx, sz = sz, crossing = false },
		{ to = corner(cx, cz, sx, -sz), cx = cx, cz = cz, sx = sx, sz = -sz, crossing = false },
	}
	local step = cellSpacing()
	if cellExists(cx + sx * step, cz) then
		table.insert(list, { to = corner(cx + sx * step, cz, -sx, sz), cx = cx + sx * step, cz = cz, sx = -sx, sz = sz, crossing = true })
	end
	if cellExists(cx, cz + sz * step) then
		table.insert(list, { to = corner(cx, cz + sz * step, sx, -sz), cx = cx, cz = cz + sz * step, sx = sx, sz = -sz, crossing = true })
	end
	return list
end

-- Choose the next leg from the corner `ped` just reached, never straight back unless it must. `walkOnly` skips
-- crossings (after waiting too long at a curb).
local function chooseLeg(ped: Ped, walkOnly: boolean)
	local cfg = Config.Pedestrians
	local here = ped.leg
	local candidates: { Leg } = {}
	local weights: { number } = {}
	local total = 0
	for _, option in options(here) do
		if (option.to - ped.from).Magnitude < 1 or (walkOnly and option.crossing) then
			continue
		end
		local w = if option.crossing then cfg.CrossWeight else cfg.WalkWeight
		table.insert(candidates, option)
		table.insert(weights, w)
		total += w
	end
	local chosen: Leg
	if #candidates == 0 then
		chosen = options(here)[1]
	else
		local roll = rng:NextNumber() * total
		chosen = candidates[#candidates]
		for i, option in candidates do
			roll -= weights[i]
			if roll <= 0 then
				chosen = option
				break
			end
		end
	end
	ped.from = here.to
	ped.at = here
	ped.leg = chosen
	ped.waiting = 0
	ped.started = false
end

-- Every car that could run someone over: player cars and traffic. Position and velocity, flattened.
local function vehicles(): { { pos: Vector3, vel: Vector3 } }
	local list: { { pos: Vector3, vel: Vector3 } } = {}
	for _, entry in VehicleService.GetAll() do
		if not entry.chassis.Anchored then
			table.insert(list, { pos = flat(entry.chassis.Position), vel = flat(entry.lastVelocity) })
		end
	end
	for _, inst in CollectionService:GetTagged(Config.Tags.Traffic) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			table.insert(list, { pos = flat(inst.Position), vel = flat(inst.AssemblyLinearVelocity) })
		end
	end
	return list
end

-- Is it safe to start across the street from a to b?
local function crossingClear(a: Vector3, b: Vector3, cars: { { pos: Vector3, vel: Vector3 } }): boolean
	local cfg = Config.Pedestrians
	local mid = (a + b) / 2
	for _, car in cars do
		local toMid = mid - car.pos
		local dist = toMid.Magnitude
		if dist < cfg.ClearDistance then
			return false
		end
		if dist < cfg.SafeDistance and car.vel:Dot(toMid.Unit) > 3 then
			return false
		end
	end
	return true
end

local function inDanger(pos: Vector3, cars: { { pos: Vector3, vel: Vector3 } }): boolean
	local cfg = Config.Pedestrians
	for _, car in cars do
		local toPed = pos - car.pos
		local dist = toPed.Magnitude
		if dist < cfg.PanicDistance and dist > 0.1 and car.vel:Dot(toPed.Unit) > 3 then
			return true
		end
	end
	return false
end

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function buildFigure(cframe: CFrame): (Model, Part, TextLabel)
	local cfg = Config.Pedestrians
	local model = Instance.new("Model")
	model.Name = "Pedestrian"
	local shirt = pick(cfg.ShirtColors)
	local torso = makePart("Torso", TORSO_SIZE, cframe, shirt, model)
	torso.Anchored = true
	model.PrimaryPart = torso
	local head = makePart("Head", HEAD_SIZE, cframe * CFrame.new(0, TORSO_SIZE.Y / 2 + HEAD_SIZE.Y / 2 + 0.1, 0), pick(cfg.SkinColors), model)
	head.Shape = Enum.PartType.Ball
	weld(torso, head)
	local pants = pick(cfg.PantsColors)
	for _, side in { -1, 1 } do
		local leg = makePart("Leg", LEG_SIZE, cframe * CFrame.new(0.45 * side, -(TORSO_SIZE.Y + LEG_SIZE.Y) / 2 + 0.1, 0), pants, model)
		weld(torso, leg)
		local arm = makePart("Arm", ARM_SIZE, cframe * CFrame.new(side * ((TORSO_SIZE.X + ARM_SIZE.X) / 2 + 0.05), 0.1, 0), shirt, model)
		weld(torso, arm)
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 36)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = cfg.BillboardDistance
	gui.Enabled = false
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 240, 200)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = ""
	label.Parent = gui
	return model, torso, label
end

local function groundY(pos: Vector3, near: number): number
	local hit = workspace:Raycast(Vector3.new(pos.X, near + RAY_UP, pos.Z), Vector3.new(0, -RAY_LENGTH, 0), groundParams)
	return if hit then hit.Position.Y else near
end

local function spotIsFree(pos: Vector3): boolean
	for _, ped in peds do
		if (ped.pos - pos).Magnitude < Config.Pedestrians.SpawnSpacing then
			return false
		end
	end
	return true
end

local function spawnPed(): boolean
	local cfg = Config.Pedestrians
	local centers = MapService.GetBlockout().CellCenters
	for _ = 1, cfg.SpawnTries do
		local cx, cz = pick(centers), pick(centers)
		if not cellExists(cx, cz) then
			continue
		end
		local sx = if rng:NextNumber() < 0.5 then -1 else 1
		local sz = if rng:NextNumber() < 0.5 then -1 else 1
		local start: Leg = { to = corner(cx, cz, sx, sz), cx = cx, cz = cz, sx = sx, sz = sz, crossing = false }
		-- Start partway along a side of the block, heading for a corner.
		local nextLeg = options(start)[rng:NextInteger(1, 2)]
		local pos = start.to:Lerp(nextLeg.to, rng:NextNumber(0.1, 0.9))
		if not spotIsFree(pos) then
			continue
		end
		local y = groundY(pos, 1)
		local model, torso, bubble = buildFigure(CFrame.lookAt(pos + Vector3.new(0, y + TORSO_HEIGHT, 0), nextLeg.to + Vector3.new(0, y + TORSO_HEIGHT, 0)))
		model.Parent = folder
		table.insert(peds, {
			model = model,
			torso = torso,
			bubble = bubble,
			pos = pos,
			leg = nextLeg,
			at = start,
			from = start.to,
			waiting = 0,
			started = false,
			phase = rng:NextNumber(0, math.pi * 2),
			hopStart = -math.huge,
			immuneUntil = 0,
			bubbleUntil = 0,
			diveStart = -math.huge,
			diveFrom = pos,
			diveTo = pos,
			decidedUntil = 0,
			forced = nil,
			standUntil = 0,
		})
		return true
	end
	return false
end

local function spawnAll()
	for _, ped in peds do
		ped.model:Destroy()
	end
	table.clear(peds)
	groundParams = MapService.StaticRaycastParams()
	for _ = 1, Config.Pedestrians.Count do
		spawnPed()
	end
end

-- Positions of everyone out in the road right now (TrafficService stops for them).
function PedestrianService.GetCrossers(): { Vector3 }
	local list: { Vector3 } = {}
	for _, ped in peds do
		if ped.leg.crossing and ped.started then
			table.insert(list, ped.pos)
		end
	end
	return list
end

local function say(ped: Ped, text: string, now: number)
	ped.bubble.Text = text
	ped.bubbleUntil = now + Config.Pedestrians.BubbleSeconds
	local gui = ped.bubble.Parent :: BillboardGui
	gui.Enabled = true
end

local function react(ped: Ped, now: number)
	local cfg = Config.Pedestrians
	ped.hopStart = now
	ped.immuneUntil = now + cfg.HitImmuneSeconds
	say(ped, pick(cfg.HitLines), now)
end

-- Odds of getting out of the way: DiveChance at low speed, down to DiveChanceAtTop at the car's top speed.
local function diveChance(entry: VehicleService.VehicleEntry, speed: number): number
	local cfg = Config.Pedestrians
	local stats = Config.Vehicles.Stats[entry.vehicleId]
	local top = if stats then stats.TopSpeed else speed
	local t = math.clamp((speed - cfg.HitMinSpeed) / math.max(1, top - cfg.HitMinSpeed), 0, 1)
	return cfg.DiveChance + (cfg.DiveChanceAtTop - cfg.DiveChance) * t
end

-- Free ground for a dive this way, up to `want` studs (stops short of a wall or building).
local function room(ped: Ped, dir: Vector3, want: number): number
	local hit = workspace:Raycast(ped.torso.Position, dir * (want + 1), groundParams)
	return if hit then math.max(0, hit.Distance - 1) else want
end

-- Dive-roll sideways out of the car's path: away from its centre line, or the other way if a wall is in the way.
local function startDive(ped: Ped, carDir: Vector3, side: Vector3, halfWidth: number, now: number)
	local cfg = Config.Pedestrians
	local lateral = side.Magnitude
	local away = if lateral > 0.1 then side.Unit else carDir:Cross(Vector3.yAxis) * (if rng:NextNumber() < 0.5 then -1 else 1)
	local clear = halfWidth + cfg.HitRadius + cfg.DiveClear
	local wantAway = math.clamp(clear - lateral, cfg.DiveMin, cfg.DiveMax)
	local wantBack = math.clamp(clear + lateral, cfg.DiveMin, cfg.DiveMax)
	local roomAway = room(ped, away, wantAway)
	local dir, dist = away, roomAway
	if roomAway < wantAway then
		local roomBack = room(ped, -away, wantBack)
		if roomBack > roomAway then
			dir, dist = -away, roomBack
		end
	end
	ped.diveStart = now
	ped.diveFrom = ped.pos
	ped.diveTo = ped.pos + Vector3.new(dir.X, 0, dir.Z) * dist
	ped.immuneUntil = now + cfg.DiveSeconds + cfg.HitImmuneSeconds
	ped.hopStart = -math.huge
	say(ped, pick(cfg.DiveLines), now)
end

-- A racer's car in this walker's path, close and closing fast: roll once for a dive.
local function dodge(ped: Ped, now: number)
	local cfg = Config.Pedestrians
	if now < ped.immuneUntil or now < ped.decidedUntil then
		return
	end
	for player, entry in VehicleService.GetAll() do
		local chassis = entry.chassis
		local vel = flat(entry.lastVelocity)
		local speed = vel.Magnitude
		if chassis.Anchored or speed < cfg.HitMinSpeed then
			continue
		end
		local dir = vel / speed
		local rel = ped.pos - flat(chassis.Position)
		local along = rel:Dot(dir)
		local side = rel - dir * along
		local half = chassis.Size / 2
		local inPath = side.Magnitude < half.X + cfg.HitRadius + cfg.DiveMargin
		local close = along > 0 and along - half.Z <= cfg.DiveDistance
		if not (inPath and close and rel.Magnitude > 0.1 and vel:Dot(rel.Unit) > cfg.HitMinSpeed) then
			continue
		end
		ped.decidedUntil = now + cfg.DecideSeconds
		local chance = diveChance(entry, speed)
		local dives = if ped.forced then ped.forced == "dive" else rng:NextNumber() < chance
		ped.forced = nil
		if dives then
			startDive(ped, dir, side, half.X, now)
		end
		if RunService:IsStudio() then
			print(string.format("[PedestrianService] %s at %d studs/s: %s (chance %.2f)", player.Name, math.floor(speed), if dives then "dived clear" else "stayed put", chance))
		end
		return
	end
end

-- A failed dive: the car clips the walker. The passenger takes the hit unless a Seatbelt or Shield covers it, the combo
-- ends, and a rival who had this car spinning or unsteerable gets the credit.
local function clip(player: Player, entry: VehicleService.VehicleEntry, ped: Ped, now: number)
	local cfg = Config.Pedestrians
	react(ped, now)
	ComboService.Reset(player, "pedestrian")
	local by = entry.lockedBy
	local attacker = if by and now < entry.lockedUntil and by ~= player then by else nil
	local lost = 0
	local shielded = false
	if PassengerService.GetLoaded(player) and not PassengerService.IsImmune(player) then
		shielded = ItemService.AbsorbHit(player, ped.torso.Position)
		if not shielded then
			lost = PassengerService.ApplyDamage(player, cfg.PassengerDamage, "pedestrian", attacker)
		end
	end
	if RunService:IsStudio() then
		local credit = if attacker then attacker.Name else "nobody"
		print(string.format("[PedestrianService] %s clipped a pedestrian: -%d HP, shield %s, credit %s", player.Name, math.round(lost), tostring(shielded), credit))
	end
end

-- Did a moving racer's car clip this walker? Box test in the car's own space.
local function checkHits(ped: Ped, now: number)
	local cfg = Config.Pedestrians
	if now < ped.immuneUntil then
		return
	end
	local waist = ped.torso.Position
	for player, entry in VehicleService.GetAll() do
		local chassis = entry.chassis
		if chassis.Anchored or flat(entry.lastVelocity).Magnitude < cfg.HitMinSpeed then
			continue
		end
		local p = chassis.CFrame:PointToObjectSpace(waist)
		local half = chassis.Size / 2
		if math.abs(p.X) < half.X + cfg.HitRadius and math.abs(p.Z) < half.Z + cfg.HitRadius and math.abs(p.Y) < half.Y + TORSO_HEIGHT + 1 then
			clip(player, entry, ped, now)
			return
		end
	end
end

-- Studio: put the nearest walker on the road ahead of this driver's car. `outcome` "dive" / "clip" forces the roll.
function PedestrianService.DebugPlaceAhead(player: Player, outcome: string?)
	local entry = VehicleService.GetEntry(player)
	if not entry or not RunService:IsStudio() then
		return
	end
	local chassis = entry.chassis
	local look = flat(chassis.CFrame.LookVector)
	local target = flat(chassis.Position) + (if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)) * 40
	local nearest: Ped? = nil
	for _, ped in peds do
		if not nearest or (ped.pos - target).Magnitude < (nearest.pos - target).Magnitude then
			nearest = ped
		end
	end
	if nearest then
		nearest.pos = target
		nearest.immuneUntil = 0
		nearest.decidedUntil = 0
		nearest.forced = outcome
		nearest.standUntil = workspace:GetServerTimeNow() + DEBUG_STAND_SECONDS
		print(string.format("[PedestrianService] walker placed 40 studs ahead of %s (outcome: %s)", player.Name, outcome or "roll"))
	end
end

local function step(ped: Ped, dt: number, now: number, cars: { { pos: Vector3, vel: Vector3 } })
	local cfg = Config.Pedestrians
	local hopT = (now - ped.hopStart) / cfg.HopSeconds
	local hopping = hopT >= 0 and hopT < 1
	local diveT = (now - ped.diveStart) / cfg.DiveSeconds
	local diving = diveT >= 0 and diveT < 1
	if diving then
		ped.pos = ped.diveFrom:Lerp(ped.diveTo, 1 - (1 - diveT) ^ 2)
	elseif ped.diveStart > -math.huge and diveT >= 1 then
		ped.pos = ped.diveTo -- landed; walk on from here
		ped.diveStart = -math.huge
	end
	if not hopping and not diving and now >= ped.standUntil then
		local leg = ped.leg
		local speed = cfg.WalkSpeed
		local go = true
		if leg.crossing and not ped.started then
			if crossingClear(ped.pos, leg.to, cars) then
				ped.started = true
			else
				go = false
				ped.waiting += dt
				if ped.waiting > cfg.MaxWait then
					-- Gave up on this street: walk on around the block from this corner.
					ped.leg = ped.at
					chooseLeg(ped, true)
				end
			end
		elseif leg.crossing and inDanger(ped.pos, cars) then
			speed *= cfg.RunMult
		end
		if go then
			local toTarget = leg.to - ped.pos
			local dist = toTarget.Magnitude
			local move = speed * dt
			if dist <= move then
				ped.pos = leg.to
				chooseLeg(ped, false)
			else
				ped.pos += toTarget.Unit * move
			end
			ped.phase += dt * speed * 1.4
		end
	end
	if now > ped.bubbleUntil then
		local gui = ped.bubble.Parent :: BillboardGui
		gui.Enabled = false
	end
	local facing = ped.leg.to - ped.pos
	local look = if facing.Magnitude > 0.1 then facing.Unit else ped.torso.CFrame.LookVector
	local y = groundY(ped.pos, ped.torso.Position.Y - TORSO_HEIGHT)
	local base = Vector3.new(ped.pos.X, y + TORSO_HEIGHT + math.abs(math.sin(ped.phase)) * BOB, ped.pos.Z)
	local cf = CFrame.lookAt(base, base + Vector3.new(look.X, 0, look.Z))
	if hopping then
		cf = cf * CFrame.new(0, math.sin(math.pi * hopT) * cfg.HopHeight, 0) * CFrame.Angles(0, math.pi * 2 * hopT, 0)
	elseif diving then
		-- a forward roll in the direction of the dive, with a little arc
		local roll = flat(ped.diveTo - ped.diveFrom)
		local heading = if roll.Magnitude > 0.1 then roll.Unit else look
		cf = CFrame.lookAt(base, base + Vector3.new(heading.X, 0, heading.Z))
			* CFrame.new(0, math.sin(math.pi * diveT) * cfg.DiveHop, 0)
			* CFrame.Angles(-math.pi * 2 * diveT, 0, 0)
	end
	ped.torso.CFrame = cf
end

function PedestrianService.Init()
	folder = MapService.GetRuntimeFolder("Pedestrians")
	MapService.OnMapLoaded:Connect(spawnAll)
end

function PedestrianService.Start()
	spawnAll()
	RunService.Heartbeat:Connect(function(dt: number)
		local now = workspace:GetServerTimeNow()
		local cars = vehicles()
		for _, ped in peds do
			dodge(ped, now)
			step(ped, dt, now, cars)
			checkHits(ped, now)
		end
	end)
end

return PedestrianService
