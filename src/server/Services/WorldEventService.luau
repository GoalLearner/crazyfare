--!strict
-- World events (Config.Chaos.Events): one per race round, StartMin..StartMax seconds after GO and Seconds long, picked
-- by Weight among those the current map has. RoundService schedules it at GO and cancels it whenever the round stops
-- playing; OnChanged tells RoundService to broadcast (the RoundState carries the event, its end and its place).
--   RushHour: TrafficService runs ExtraTraffic more cars until it ends.
--   Drawbridge: the City's drawbridge leaves (Config.MapFeatures.Drawbridge, tagged Drawbridge) turn up about their
--     outer ends to MaxAngle over RiseSeconds and back down over the last LowerSeconds: a peak to jump.
--   Parade: a line of floats rolls along one road, solid to players; bots and traffic stop for them.
--   HydrantBurst: every curb hydrant (Config.MapFeatures.Hydrants) jets water into its lane; a car in a jet is thrown
--     up (a player's own car through ItemEvent "Launched", a bot through BotService.Launch).
--   MoneyTruck: an armored truck parks in a random junction and spills coins worth MinDollars..MaxDollars each; driving
--     through one banks it (players and bots). Bots and traffic stop for the truck.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Money = require(ReplicatedStorage.Shared.Money)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Racers = require(script.Parent.Parent.Racers)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local FareService = require(script.Parent.FareService)
local TrafficService = require(script.Parent.TrafficService)
local BotService = require(script.Parent.BotService)

local WorldEventService = {}

local onChanged: Signal.Signal<nil> = Signal.new()
WorldEventService.OnChanged = onChanged -- an event started or ended

type Def = { Id: string, Name: string, Sub: string, Weight: number, Maps: { [string]: boolean }? }
type Leaf = { part: BasePart, side: number, hinge: Vector3, rest: CFrame }
type Coin = { part: Part, cents: number, position: Vector3 }
type Blocker = { position: Vector3, velocity: Vector3, clearance: number }

local rng = Random.new()
local folder: Folder
local itemEvent: RemoteEvent
local fareEvent: RemoteEvent
local scheduledAt: number? = nil
local active: Def? = nil
local startedAt = 0
local endsAt = 0
local eventAt: Vector3? = nil
local leaves: { Leaf } = {}
local floats: { Model } = {}
local jets: { { part: Part, at: Vector3 } } = {}
local launchedAt: { [Player]: number } = {}
local coins: { Coin } = {}
local truck: Model? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function features(): Config.MapFeatures?
	local mapCfg = (Config.Map :: any)[MapService.GetCurrentMap()]
	return if typeof(mapCfg) == "table" and mapCfg.Blockout then mapCfg.Blockout.Features else nil
end

local function groundAt(x: number, z: number): number
	return MapService.GroundY(Vector3.new(x, 0, z), 0)
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance, solid: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = true
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function label(parent: BasePart, text: string, color: Color3, sizePx: number, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(sizePx * 2, sizePx)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.Text = text
	t.Parent = gui
end

-- Parade floats and the money truck, for bots (with clearance) and traffic.
local function pushBlockers()
	local forBots: { Blocker } = {}
	local forTraffic: { { position: Vector3, velocity: Vector3 } } = {}
	local def = active
	if def and def.Id == "Parade" then
		local cfg = Config.Chaos.Events.Parade
		local dir = if cfg.Axis == "Z" then Vector3.xAxis else Vector3.zAxis
		for _, model in floats do
			local pos = flat(model:GetPivot().Position)
			table.insert(forBots, { position = pos, velocity = dir * cfg.Speed, clearance = cfg.Size.Z / 2 + Config.Bots.CarClearance })
			table.insert(forTraffic, { position = pos, velocity = dir * cfg.Speed })
		end
	end
	local at = eventAt
	if def and def.Id == "MoneyTruck" and at then
		local cfg = Config.Chaos.Events.MoneyTruck
		table.insert(forBots, { position = at, velocity = Vector3.zero, clearance = cfg.Size.X / 2 + Config.Bots.CarClearance })
		table.insert(forTraffic, { position = at, velocity = Vector3.zero })
	end
	BotService.SetBlockers(forBots)
	TrafficService.SetBlockers(forTraffic)
end

-- Drawbridge ------------------------------------------------------------------------------------------------------

local function startDrawbridge()
	table.clear(leaves)
	for _, inst in CollectionService:GetTagged(Config.Tags.Drawbridge) do
		local side = inst:GetAttribute("Side")
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) and typeof(side) == "number" then
			local rest = inst.CFrame
			local hinge = (rest * CFrame.new(0, -inst.Size.Y / 2, side * inst.Size.Z / 2)).Position
			table.insert(leaves, { part = inst, side = side, hinge = hinge, rest = rest })
		end
	end
end

local function setLeaves(angle: number)
	for _, leaf in leaves do
		local size = leaf.part.Size
		leaf.part.CFrame = CFrame.new(leaf.hinge) * CFrame.Angles(leaf.side * angle, 0, 0) * CFrame.new(0, size.Y / 2, -leaf.side * size.Z / 2)
	end
end

local function stepDrawbridge(t: number)
	local cfg = Config.Chaos.Events.Drawbridge
	local up = math.clamp((t - startedAt) / cfg.RiseSeconds, 0, 1) * math.clamp((endsAt - t) / cfg.LowerSeconds, 0, 1)
	setLeaves(math.rad(cfg.MaxAngle) * up)
end

local function stopDrawbridge()
	for _, leaf in leaves do
		leaf.part.CFrame = leaf.rest
	end
	table.clear(leaves)
end

-- Parade ----------------------------------------------------------------------------------------------------------

local function buildFloat(index: number): Model
	local cfg = Config.Chaos.Events.Parade
	local color = cfg.Colors[(index - 1) % #cfg.Colors + 1]
	local model = Instance.new("Model")
	model.Name = "ParadeFloat"
	local size = cfg.Size -- X along the road, Z across it
	local base = part("Float", Vector3.new(size.Z, size.Y, size.X), CFrame.new(0, 0, 0), color, model, true)
	base.Material = Enum.Material.SmoothPlastic
	model.PrimaryPart = base
	-- a skirt, a stage and balloons on sticks; every third float carries a giant star
	part("Skirt", Vector3.new(size.Z + 0.6, 1, size.X + 0.6), CFrame.new(0, -size.Y / 2 + 0.5, 0), Color3.fromRGB(250, 250, 250), model, false)
	part("Stage", Vector3.new(size.Z * 0.6, 2, size.X * 0.5), CFrame.new(0, size.Y / 2 + 1, 0), Color3.fromRGB(255, 255, 255), model, true)
	for k = -1, 1 do
		local stick = part("Stick", Vector3.new(0.3, 7, 0.3), CFrame.new(k * size.Z / 3, size.Y / 2 + 3.5, size.X / 3), Color3.fromRGB(240, 240, 240), model, false)
		local balloon = part("Balloon", Vector3.new(3, 3.6, 3), stick.CFrame * CFrame.new(0, 4.6, 0), cfg.Colors[(index + k + 2) % #cfg.Colors + 1], model, false)
		balloon.Shape = Enum.PartType.Ball
		balloon.Material = Enum.Material.SmoothPlastic
	end
	if index % 3 == 0 then
		local star = part("Star", Vector3.new(5, 5, 1.2), CFrame.new(0, size.Y / 2 + 5, 0) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 220, 60), model, false)
		star.Material = Enum.Material.Neon
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= base then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = base
			weld.Part1 = p
			weld.Parent = p
			p.Anchored = false
		end
	end
	model.Parent = folder
	return model
end

local function startParade()
	local cfg = Config.Chaos.Events.Parade
	table.clear(floats)
	for i = 1, cfg.Floats do
		table.insert(floats, buildFloat(i))
	end
end

local function stepParade(t: number)
	local cfg = Config.Chaos.Events.Parade
	local travelled = cfg.Speed * (t - startedAt)
	local dir = if cfg.Axis == "Z" then Vector3.xAxis else Vector3.zAxis
	for i, model in floats do
		local along = cfg.From + travelled - (i - 1) * cfg.Spacing
		local x = if cfg.Axis == "Z" then along else cfg.Coord
		local z = if cfg.Axis == "Z" then cfg.Coord else along
		local pos = Vector3.new(x, groundAt(x, z) + cfg.Size.Y / 2 + 0.5, z)
		model:PivotTo(CFrame.lookAt(pos, pos + dir))
	end
end

local function stopParade()
	for _, model in floats do
		model:Destroy()
	end
	table.clear(floats)
end

-- Hydrants --------------------------------------------------------------------------------------------------------

local function startHydrants()
	local f = features()
	local cfg = Config.Chaos.Events.HydrantBurst
	table.clear(jets)
	table.clear(launchedAt)
	if not f then
		return
	end
	for _, h in f.Hydrants do
		local at = Vector3.new(h.X + h.DX * f.HydrantSpray, 0, h.Z + h.DZ * f.HydrantSpray)
		local y = groundAt(at.X, at.Z)
		local jet = part("HydrantJet", Vector3.new(cfg.JetHeight, cfg.JetWidth, cfg.JetWidth), CFrame.new(at.X, y + cfg.JetHeight / 2, at.Z) * CFrame.Angles(0, 0, math.rad(90)), cfg.JetColor, folder, false)
		jet.Shape = Enum.PartType.Cylinder
		jet.Material = Enum.Material.Glass
		jet.Transparency = 0.35
		local spray = Instance.new("ParticleEmitter")
		spray.Rate = 45
		spray.Lifetime = NumberRange.new(0.6, 1)
		spray.Speed = NumberRange.new(8, 16)
		spray.SpreadAngle = Vector2.new(35, 35)
		spray.Acceleration = Vector3.new(0, -60, 0)
		spray.Size = NumberSequence.new(1.2, 0.2)
		spray.Color = ColorSequence.new(cfg.JetColor, Color3.fromRGB(255, 255, 255))
		spray.Transparency = NumberSequence.new(0.2, 1)
		spray.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis points up after its turn
		spray.Parent = jet
		table.insert(jets, { part = jet, at = at })
	end
end

local function stepHydrants(t: number)
	local cfg = Config.Chaos.Events.HydrantBurst
	for player, entry in VehicleService.GetAll() do
		if entry.chassis.Anchored or t - (launchedAt[player] or -math.huge) < cfg.Cooldown then
			continue
		end
		local pos = flat(entry.chassis.Position)
		for _, jet in jets do
			if (pos - jet.at).Magnitude <= cfg.Radius then
				launchedAt[player] = t
				entry.crashImmuneUntil = math.max(entry.crashImmuneUntil, t + cfg.Cooldown)
				if Racers.IsBot(player) then
					BotService.Launch(player, cfg.LaunchSpeed)
				else
					itemEvent:FireClient(player, { kind = "Launched", push = Vector3.new(0, cfg.LaunchSpeed, 0) })
				end
				break
			end
		end
	end
end

local function stopHydrants()
	for _, jet in jets do
		jet.part:Destroy()
	end
	table.clear(jets)
	table.clear(launchedAt)
end

-- Money truck -----------------------------------------------------------------------------------------------------

local function startMoneyTruck()
	local cfg = Config.Chaos.Events.MoneyTruck
	local coords = MapService.GetBlockout().RoadCoords
	local inner: { number } = {}
	for i = 2, #coords - 1 do
		table.insert(inner, coords[i])
	end
	local cx, cz = inner[rng:NextInteger(1, #inner)], inner[rng:NextInteger(1, #inner)]
	local center = Vector3.new(cx, 0, cz)
	eventAt = center
	local y = groundAt(cx, cz)
	local model = Instance.new("Model")
	model.Name = "MoneyTruck"
	local body = part("TruckBody", cfg.Size, CFrame.new(cx, y + cfg.Size.Y / 2 + 0.6, cz) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0), Color3.fromRGB(70, 90, 80), model, true)
	body.Material = Enum.Material.DiamondPlate
	model.PrimaryPart = body
	local stripe = part("TruckStripe", Vector3.new(cfg.Size.X + 0.1, 1, cfg.Size.Z * 0.7), body.CFrame * CFrame.new(0, 0.5, 0), Color3.fromRGB(250, 205, 50), model, false)
	stripe.Material = Enum.Material.Neon
	label(body, "$$$", Config.Golden.Color, 40, cfg.Size.Y / 2 + 3)
	model.Parent = folder
	truck = model
	table.clear(coins)
	for _ = 1, cfg.Pickups do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(cfg.ScatterMin, cfg.ScatterMax)
		local at = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * r
		local cents = Money.Cents(rng:NextInteger(cfg.MinDollars, cfg.MaxDollars))
		local coin = part("Coin", Vector3.new(0.5, 2.8, 2.8), CFrame.new(at.X, groundAt(at.X, at.Z) + 1.8, at.Z) * CFrame.Angles(0, angle, 0), Config.Golden.Color, folder, false)
		coin.Shape = Enum.PartType.Cylinder
		coin.Material = Enum.Material.Neon
		label(coin, Money.Format(cents), Config.Golden.Color, 22, 2.4)
		table.insert(coins, { part = coin, cents = cents, position = at })
	end
end

local function stepMoneyTruck()
	local cfg = Config.Chaos.Events.MoneyTruck
	for player, entry in VehicleService.GetAll() do
		if entry.chassis.Anchored then
			continue
		end
		local pos = flat(entry.chassis.Position)
		for i = #coins, 1, -1 do
			local coin = coins[i]
			if (pos - coin.position).Magnitude <= cfg.PickupRadius then
				FareService.AddCash(player, coin.cents)
				if not Racers.IsBot(player) then
					fareEvent:FireClient(player, { kind = "Cash", payout = coin.cents })
				end
				coin.part:Destroy()
				table.remove(coins, i)
			end
		end
	end
end

local function stopMoneyTruck()
	for _, coin in coins do
		coin.part:Destroy()
	end
	table.clear(coins)
	local model = truck
	if model then
		model:Destroy()
	end
	truck = nil
end

-- Running one -----------------------------------------------------------------------------------------------------

local function stop()
	local def = active
	if not def then
		return
	end
	if def.Id == "RushHour" then
		TrafficService.EndSurge()
	elseif def.Id == "Drawbridge" then
		stopDrawbridge()
	elseif def.Id == "Parade" then
		stopParade()
	elseif def.Id == "HydrantBurst" then
		stopHydrants()
	elseif def.Id == "MoneyTruck" then
		stopMoneyTruck()
	end
	active = nil
	eventAt = nil
	pushBlockers()
	onChanged:Fire()
end

local function start(def: Def)
	stop()
	active = def
	startedAt = now()
	endsAt = startedAt + Config.Chaos.Events.Seconds
	eventAt = nil
	if def.Id == "RushHour" then
		TrafficService.Surge(Config.Chaos.Events.RushHour.ExtraTraffic)
	elseif def.Id == "Drawbridge" then
		startDrawbridge()
	elseif def.Id == "Parade" then
		startParade()
	elseif def.Id == "HydrantBurst" then
		startHydrants()
	elseif def.Id == "MoneyTruck" then
		startMoneyTruck()
	end
	pushBlockers()
	if RunService:IsStudio() then
		print(string.format("[WorldEventService] %s for %d s", def.Id, Config.Chaos.Events.Seconds))
	end
	onChanged:Fire()
end

-- A weighted pick among the events this map has.
local function pick(): Def?
	local mapName = MapService.GetCurrentMap()
	local pool: { Def } = {}
	local total = 0
	for _, def in Config.Chaos.Events.List do
		local maps = def.Maps
		if not maps or maps[mapName] then
			table.insert(pool, def)
			total += def.Weight
		end
	end
	if total <= 0 then
		return nil
	end
	local r = rng:NextNumber() * total
	for _, def in pool do
		r -= def.Weight
		if r <= 0 then
			return def
		end
	end
	return pool[#pool]
end

-- A race round just went GO: its event starts StartMin..StartMax seconds from now.
function WorldEventService.ScheduleRound()
	local cfg = Config.Chaos.Events
	stop()
	scheduledAt = now() + rng:NextNumber(cfg.StartMin, cfg.StartMax)
end

-- The round stopped playing: no event now, none coming.
function WorldEventService.Cancel()
	scheduledAt = nil
	stop()
end

-- The event running (its id, when it ends, where it is when it has one place), or nil.
function WorldEventService.GetActive(): (string?, number, Vector3?)
	local def = active
	if def then
		return def.Id, endsAt, eventAt
	end
	return nil, 0, nil
end

-- Studio: start this event now (during a round).
function WorldEventService.DebugStart(id: string)
	if not RunService:IsStudio() then
		return
	end
	for _, def in Config.Chaos.Events.List do
		if def.Id == id then
			scheduledAt = nil
			start(def)
			return
		end
	end
end

-- Studio: this driver's car where the running event happens: on a coin, in a jet, on the drawbridge's north approach
-- facing it, or on the parade road ahead of the floats.
function WorldEventService.DebugTeleport(player: Player)
	local entry = VehicleService.GetEntry(player)
	local def = active
	if not RunService:IsStudio() or not entry or entry.chassis.Anchored or not def then
		return
	end
	local at: Vector3? = nil
	local look = Vector3.new(0, 0, -1)
	local f = features()
	if def.Id == "MoneyTruck" and coins[1] then
		at = coins[1].position
	elseif def.Id == "HydrantBurst" and jets[1] then
		at = jets[1].at
	elseif def.Id == "Drawbridge" and f then
		local d = f.Drawbridge
		at = Vector3.new(d.X - 6, 0, d.Z - d.LeafLength - 110) -- the southbound lane, north of the bridge
		look = Vector3.new(0, 0, 1)
	elseif def.Id == "Parade" and floats[1] then
		local cfg = Config.Chaos.Events.Parade
		local lead = flat(floats[1]:GetPivot().Position)
		local dir = if cfg.Axis == "Z" then Vector3.xAxis else Vector3.zAxis
		at = lead + dir * 60
		look = -dir
	end
	if at then
		local pos = Vector3.new(at.X, groundAt(at.X, at.Z) + Config.Chassis.ResetLift, at.Z)
		VehicleService.Teleport(entry, CFrame.lookAt(pos, pos + look))
	end
end

function WorldEventService.Init()
	folder = MapService.GetRuntimeFolder("Events")
	itemEvent = Remotes.Get("ItemEvent")
	fareEvent = Remotes.Get("FareEvent")
	MapService.OnMapLoaded:Connect(function()
		WorldEventService.Cancel()
	end)
end

function WorldEventService.Start()
	RunService.Heartbeat:Connect(function()
		local t = now()
		local due = scheduledAt
		if due and t >= due then
			scheduledAt = nil
			local def = pick()
			if def then
				start(def)
			end
		end
		local def = active
		if not def then
			return
		end
		if t >= endsAt then
			stop()
			return
		end
		if def.Id == "Drawbridge" then
			stepDrawbridge(t)
		elseif def.Id == "Parade" then
			stepParade(t)
			pushBlockers()
		elseif def.Id == "HydrantBurst" then
			stepHydrants(t)
		elseif def.Id == "MoneyTruck" then
			stepMoneyTruck()
		end
	end)
end

return WorldEventService
