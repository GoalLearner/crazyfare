--!strict
-- NPC passengers: spawning by tier weighting, personality (Config.PassengerTypes) and the rare Golden Fare, boarding,
-- HP (damage and crashes; no regen), bailing and walking back, delivery thanks. FareService owns the money side and
-- listens to OnBailed; RiderService puts the passenger in the cab on OnBoarded and takes them out on OnUnloaded.
-- Player fares (Config.PlayerFare): a person on foot who hailed a cab is a passenger too (`rider` set). Their marker is a
-- gold ring and a TAXI! sign at the curb; aboard, their own avatar rides along (the RidingWith attribute; every client
-- seats it in that cab), and every way the ride ends puts them back on their feet beside the cab (OnRiderFreed).

local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local Events = require(ReplicatedStorage.Shared.Events)
local Ticking = require(ReplicatedStorage.Shared.Ticking)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local MonetizationService = require(script.Parent.MonetizationService)

export type Npc = {
	id: number,
	model: Model,
	torso: BasePart,
	tier: string,
	kind: string, -- Config.PassengerTypes.Kinds key
	golden: boolean, -- the Golden Fare: triple pay, gold beam, everyone told
	state: number, -- 0 available, 1 boarded, 2 walking back, 3 thanking
	pickupIndex: number, -- point it stands at (or is walking to)
	position: Vector3,
	destinationIndex: number?, -- set on first claim; survives a bail
	hp: number,
	maxHp: number,
	boardedBy: Player?,
	bubble: TextLabel,
	icon: TextLabel,
	walkTween: Tween?,
	riders: number, -- people in the group (2+ = a carpool, Config.Chaos.Carpool)
	group: TextLabel?, -- "CARPOOL x3" over a waiting group
	ticking: boolean, -- late, with an alarm clock: the fare drops every second (Config.Chaos.Ticking)
	rider: Player?, -- a player fare: the person who hailed (their avatar rides; no NPC figure)
	card: string?, -- a Weirdo card's bonus fare (Config.Cosmetics.Cards key)
	reservedFor: Player?, -- that card's owner: only they can pick it up until revealAt
	revealAt: number?, -- server time it opens to everyone
}

local PassengerService = {}

local onBailed: Signal.Signal<Player, Npc, string, Player?> = Signal.new()
local onDamaged: Signal.Signal<Player, number, string> = Signal.new()
local onBoarded: Signal.Signal<Player, Npc> = Signal.new()
local onUnloaded: Signal.Signal<Player, Npc> = Signal.new()
local onGoldenSpawned: Signal.Signal<Npc> = Signal.new()
local onRiderFreed: Signal.Signal<Player, Player?, string> = Signal.new()
PassengerService.OnBailed = onBailed -- (victim, npc, reason "hp" | "timeout", attacker when a rival caused it)
PassengerService.OnDamaged = onDamaged -- (player, amount, source)
PassengerService.OnBoarded = onBoarded -- (player, npc) the passenger got in
PassengerService.OnUnloaded = onUnloaded -- (player, npc) the passenger got out (delivered, bailed, released)
PassengerService.OnGoldenSpawned = onGoldenSpawned -- (npc) a Golden Fare just appeared at a curb
-- (rider, driver or nil, reason) a player fare is over: "delivered" | "hp" | "timeout" | "left" | "released" | "roundover"
-- | "cancelled" | "cleared"
PassengerService.OnRiderFreed = onRiderFreed

local npcs: { [number]: Npc } = {}
local loadedByPlayer: { [Player]: Npc } = {}
local lastDamageAt: { [Player]: number } = {}
local immuneUntil: { [Player]: number } = {} -- Seatbelt
local lastAttacker: { [Player]: Player } = {} -- who last damaged this player's passenger
local npcAtPickup: { [number]: number } = {} -- pickupIndex -> npcId (standing or walking there)
local nextId = 1
local rng = Random.new()
local folder: Folder

local SKIN = Color3.fromRGB(230, 190, 160)
local PANTS = Color3.fromRGB(50, 60, 90)

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
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = a.CFrame:ToObjectSpace(b.CFrame)
	w.Parent = b
end

local function makeLabel(parent: Instance, name: string, size: UDim2, offset: Vector3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffset = offset
	gui.AlwaysOnTop = true
	gui.MaxDistance = Config.Hud.NpcBillboardDistance
	gui.LightInfluence = 0
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = gui
	return label
end

-- Torso center sits 2.5 above the ground point; the whole figure is welded to the anchored torso.
local function standCFrame(groundPos: Vector3, look: Vector3): CFrame
	local pos = groundPos + Vector3.new(0, 2.5, 0)
	return CFrame.lookAt(pos, pos + VecUtil.FlatUnit(look))
end

-- The Golden Fare's marks: a gold ring at the feet, a tall gold pillar over the curb, sparkles and a glow.
local function addGoldenMarks(model: Model, torso: BasePart, torsoCf: CFrame)
	local g = Config.Golden
	local ring = makePart("GoldenRing", Vector3.new(0.3, g.RingRadius * 2, g.RingRadius * 2), torsoCf * CFrame.new(0, -2.4, 0) * CFrame.Angles(0, 0, math.pi / 2), g.Color, model)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	weld(torso, ring)
	local beam = makePart("GoldenBeam", Vector3.new(g.BeamHeight, g.BeamWidth, g.BeamWidth), torsoCf * CFrame.new(0, g.BeamHeight / 2 - 2.5, 0) * CFrame.Angles(0, 0, math.pi / 2), g.Color, model)
	beam.Shape = Enum.PartType.Cylinder
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.55
	beam.CastShadow = false
	weld(torso, beam)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(g.Color)
	sparkles.LightEmission = 1
	sparkles.Rate = 18
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(2, 5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.5, 0)
	sparkles.Parent = torso
	local light = Instance.new("PointLight")
	light.Color = g.Color
	light.Range = 14
	light.Brightness = 2
	light.Parent = torso
end

local function buildModel(npc: Npc, groundPos: Vector3, look: Vector3): (Model, BasePart, TextLabel, TextLabel)
	local tierDef = Config.Fares.Tiers[npc.tier]
	local kindDef = Config.PassengerTypes.Kinds[npc.kind] or Config.PassengerTypes.Kinds.Regular
	local card = if npc.card then Config.Cosmetics.Cards[npc.card] else nil
	local badgeColor = if npc.golden then Config.Golden.Color elseif card then card.Shirt else tierDef.Color
	local model = Instance.new("Model")
	model.Name = "NPC_" .. npc.id
	model:SetAttribute("NpcId", npc.id)
	model:SetAttribute("Tier", npc.tier)
	model:SetAttribute("Kind", npc.kind)
	model:SetAttribute("Golden", npc.golden)
	model:SetAttribute("Ticking", npc.ticking)
	-- a Weirdo card's fare: clients hide its badge from everyone but the owner until RevealAt (WeirdoController)
	local reservedFor = npc.reservedFor
	if card and reservedFor then
		model:SetAttribute("Card", npc.card)
		model:SetAttribute("ReservedFor", reservedFor.UserId)
		model:SetAttribute("RevealAt", npc.revealAt or 0)
	end
	CollectionService:AddTag(model, Config.Tags.Npc)

	local torsoCf = standCFrame(groundPos, look)
	local torso = makePart("Torso", Vector3.new(1.6, 1.8, 0.9), torsoCf, badgeColor, model)
	torso.Anchored = true
	model.PrimaryPart = torso

	local head = makePart("Head", Vector3.new(1.1, 1.1, 1.1), torsoCf * CFrame.new(0, 1.45, 0), SKIN, model)
	head.Shape = Enum.PartType.Ball
	weld(torso, head)
	for _, side in { -1, 1 } do
		local leg = makePart("Leg", Vector3.new(0.7, 1.6, 0.7), torsoCf * CFrame.new(0.45 * side, -1.7, 0), PANTS, model)
		weld(torso, leg)
		local arm = makePart("Arm", Vector3.new(0.5, 1.5, 0.5), torsoCf * CFrame.new(1.05 * side, 0.1, 0), badgeColor, model)
		weld(torso, arm)
	end
	if npc.golden then
		addGoldenMarks(model, torso, torsoCf)
	end
	-- a weirdo's costume: the shirt (torso and arms, above) and a hat in the card's colors
	if card then
		local hat = makePart("Hat", Config.Cosmetics.Bonus.HatSize, torsoCf * CFrame.new(0, 2.25, 0), card.Hat, model)
		weld(torso, hat)
	end
	-- A carpool: the others stand beside them (welded, so they walk and ride along), one model each so a stop takes one
	local carpool = Config.Chaos.Carpool
	for k = 2, npc.riders do
		local buddy = Instance.new("Model")
		buddy.Name = "Buddy"
		local side = if k % 2 == 0 then 1 else -1
		local offset = CFrame.new(side * carpool.Spacing * math.ceil((k - 1) / 2), -0.15, 0.4)
		local shirt = carpool.Shirts[(k - 2) % #carpool.Shirts + 1]
		local bTorso = makePart("Torso", Vector3.new(1.5, 1.6, 0.85), torsoCf * offset, shirt, buddy)
		local bHead = makePart("Head", Vector3.new(1.05, 1.05, 1.05), torsoCf * offset * CFrame.new(0, 1.35, 0), SKIN, buddy)
		bHead.Shape = Enum.PartType.Ball
		local bLegs = makePart("Leg", Vector3.new(1.3, 1.5, 0.65), torsoCf * offset * CFrame.new(0, -1.55, 0), PANTS, buddy)
		for _, p in { bTorso, bHead, bLegs } do
			weld(torso, p)
		end
		buddy.Parent = model
	end
	-- A ticking fare hugs a giant alarm clock to their chest, face out (below the face)
	if npc.ticking then
		local clock = Ticking.Clock(Config.Chaos.Ticking.ClockSize)
		clock:PivotTo(torsoCf * CFrame.new(0, -0.2, -0.85) * CFrame.Angles(0, math.pi, 0))
		weld(torso, clock.PrimaryPart :: BasePart)
		clock.Parent = model
	end

	-- The badge: tier color ring, the kind's icon inside ($, a bolt, a nervous face; a star for the Golden Fare)
	local iconSize = if npc.golden then 60 elseif card then Config.Cosmetics.Bonus.IconSize else 46
	local icon = makeLabel(head, "Icon", UDim2.fromOffset(iconSize, iconSize), Vector3.new(0, 1.6, 0))
	icon.Text = if npc.golden then Config.Golden.Icon elseif card then card.Icon else kindDef.Icon
	icon.TextColor3 = badgeColor
	local iconFrame = icon.Parent :: BillboardGui
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	ring.BackgroundTransparency = 0.25
	ring.ZIndex = 0
	ring.Parent = iconFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = badgeColor
	stroke.Parent = ring
	icon.ZIndex = 2

	-- A word over the badge (CARPOOL x3, TICK TOCK): centered on the badge and stacked above it in pixels, so the two
	-- never overlap however far away they are
	local function tag(name: string, text: string, color: Color3): TextLabel
		local label = makeLabel(head, name, UDim2.fromOffset(120, iconSize + 52), Vector3.new(0, 1.6, 0))
		label.Size = UDim2.new(1, 0, 0, 22)
		label.Text = text
		label.TextColor3 = color
		return label
	end
	if npc.riders > 1 then
		npc.group = tag("Group", string.format(carpool.Label, npc.riders), carpool.Color)
	end
	if npc.ticking then
		tag("Ticking", Config.Chaos.Ticking.Label, Config.Chaos.Ticking.Color)
	end
	if card then
		tag("Card", card.Name, card.Shirt)
	end

	local bubble = makeLabel(head, "Bubble", UDim2.fromOffset(260, 40), Vector3.new(0, 3.2, 0))
	bubble.Text = ""
	bubble.Font = Enum.Font.GothamBold
	bubble.TextColor3 = Color3.fromRGB(255, 240, 200)
	;(bubble.Parent :: BillboardGui).Enabled = false

	model.Parent = folder
	return model, torso, icon, bubble
end

local function showBubble(npc: Npc, text: string, seconds: number)
	local gui = npc.bubble.Parent :: BillboardGui
	npc.bubble.Text = text
	gui.Enabled = true
	local shownId = npc.id
	task.delay(seconds, function()
		if npcs[shownId] == npc and gui.Parent then
			gui.Enabled = false
		end
	end)
end

local function randomLine(lines: { string }): string
	return lines[rng:NextInteger(1, #lines)]
end

local function pickTier(distanceFromCenter: number): string
	local band = Config.Fares.TierWeightsByDistance[#Config.Fares.TierWeightsByDistance]
	for _, b in Config.Fares.TierWeightsByDistance do
		if distanceFromCenter <= b.MaxDistance then
			band = b
			break
		end
	end
	local total = band.Green + band.Yellow + band.Red
	local r = rng:NextNumber() * total
	if r < band.Green then
		return "Green"
	elseif r < band.Green + band.Yellow then
		return "Yellow"
	end
	return "Red"
end

local function unload(player: Player): Npc?
	local npc = loadedByPlayer[player]
	if not npc then
		return nil
	end
	loadedByPlayer[player] = nil
	npc.boardedBy = nil
	immuneUntil[player] = nil
	lastAttacker[player] = nil
	onUnloaded:Fire(player, npc)
	return npc
end

-- Where a passenger steps out: beside the car, on the ground.
local function exitPose(player: Player, fallback: Vector3): (Vector3, Vector3)
	local entry = VehicleService.GetEntry(player)
	if not entry then
		return fallback, Vector3.new(0, 0, -1)
	end
	local cf = entry.chassis.CFrame
	local right = VecUtil.FlatUnit(cf.RightVector, Vector3.new(1, 0, 0))
	local flat = Vector3.new(cf.Position.X, 0, cf.Position.Z) + right * 6
	local y = MapService.GroundY(Vector3.new(flat.X, cf.Position.Y, flat.Z), 0.5)
	return Vector3.new(flat.X, y, flat.Z), VecUtil.FlatUnit(cf.LookVector)
end

local function destroyNpc(npc: Npc)
	if npcs[npc.id] ~= npc then
		return
	end
	npcs[npc.id] = nil
	if npcAtPickup[npc.pickupIndex] == npc.id then
		npcAtPickup[npc.pickupIndex] = nil
	end
	if npc.walkTween then
		npc.walkTween:Cancel()
	end
	npc.model:Destroy()
end

-- A player fare's person back on their feet beside the cab (or where they hailed, if there's no cab): RidingWith
-- cleared, so every client stops seating them. A bail also stamps EjectedAt, which the rider's client plays as a toss.
local function freeRider(npc: Npc, driver: Player?, reason: string)
	local rider = npc.rider
	if not rider then
		return
	end
	npc.rider = nil
	if rider.Parent then
		rider:SetAttribute("RidingWith", nil)
		local character = rider.Character
		if character and driver and npc.state == 1 then
			local entry = VehicleService.GetEntry(driver)
			if entry then
				local cf = entry.chassis.CFrame
				local right = VecUtil.FlatUnit(cf.RightVector, Vector3.new(1, 0, 0))
				local flat = Vector3.new(cf.Position.X, 0, cf.Position.Z) + right * Config.PlayerFare.EjectSide
				local y = MapService.GroundY(Vector3.new(flat.X, cf.Position.Y, flat.Z), 0.5)
				local at = Vector3.new(flat.X, y + 3, flat.Z)
				character:PivotTo(CFrame.lookAt(at, at + VecUtil.FlatUnit(cf.LookVector)))
			end
		end
		if reason == "hp" or reason == "timeout" then
			rider:SetAttribute("EjectedAt", workspace:GetServerTimeNow())
		end
	end
	onRiderFreed:Fire(rider, driver, reason)
end

local function walkTo(npc: Npc, point: MapService.Point)
	if npcAtPickup[npc.pickupIndex] == npc.id then
		npcAtPickup[npc.pickupIndex] = nil
	end
	npc.pickupIndex = point.index
	npcAtPickup[point.index] = npc.id
	npc.state = 2
	local groundY = MapService.GroundY(point.position, point.position.Y)
	local target = Vector3.new(point.position.X, groundY, point.position.Z)
	local distance = VecUtil.FlatDistance(target, npc.position)
	local duration = math.max(0.5, distance / Config.Passenger.BailWalkSpeed)
	local tween = TweenService:Create(npc.torso, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = standCFrame(target, point.cframe.LookVector),
	})
	npc.walkTween = tween
	tween.Completed:Connect(function()
		if npcs[npc.id] ~= npc or npc.walkTween ~= tween then
			return
		end
		npc.walkTween = nil
		npc.position = target
		npc.state = 0
	end)
	tween:Play()
end

local function pickKind(): string
	local kinds = Config.PassengerTypes
	local total = 0
	for _, kind in kinds.Order do
		total += kinds.Kinds[kind].Weight
	end
	local r = rng:NextNumber() * total
	for _, kind in kinds.Order do
		r -= kinds.Kinds[kind].Weight
		if r <= 0 then
			return kind
		end
	end
	return kinds.Order[1]
end

local function goldenInPlay(): boolean
	for _, npc in npcs do
		if npc.golden and npc.state ~= 3 then
			return true
		end
	end
	return false
end

-- `golden` true forces a Golden Fare (debug); nil rolls Config.Golden.Chance (more during a GOLDEN HOUR event) while
-- none is in play. `riders` and `ticking` likewise force a carpool or a ticking fare; nil rolls their chances.
function PassengerService.SpawnAt(point: MapService.Point, tier: string, golden: boolean?, riders: number?, ticking: boolean?): Npc
	local tierDef = Config.Fares.Tiers[tier]
	local chance = Config.Golden.Chance * Events.GoldenChanceMult(os.time())
	local isGolden = if golden ~= nil then golden else (not goldenInPlay() and rng:NextNumber() < chance)
	local id = nextId
	nextId += 1
	local groundY = MapService.GroundY(point.position, point.position.Y)
	local groundPos = Vector3.new(point.position.X, groundY, point.position.Z)
	local count = riders or (if not isGolden and rng:NextNumber() < Config.Chaos.Carpool.Chance then rng:NextInteger(2, Config.Chaos.Carpool.MaxRiders) else 1)
	local isTicking = if ticking ~= nil then ticking else (not isGolden and count == 1 and rng:NextNumber() < Config.Chaos.Ticking.Chance)
	local npc = {
		id = id,
		tier = tier,
		kind = if isGolden then "Regular" else pickKind(),
		golden = isGolden,
		state = 0,
		pickupIndex = point.index,
		position = groundPos,
		hp = tierDef.Hp,
		maxHp = tierDef.Hp,
		riders = count,
		ticking = isTicking,
	} :: any
	local model, torso, icon, bubble = buildModel(npc, groundPos, point.cframe.LookVector)
	npc.model = model
	npc.torso = torso
	npc.icon = icon
	npc.bubble = bubble
	local typed = npc :: Npc
	npcs[id] = typed
	npcAtPickup[point.index] = id
	if isGolden then
		onGoldenSpawned:Fire(typed)
	end
	return typed
end

-- A carpool stop: one of the group gets out (the passenger aboard keeps the rest).
function PassengerService.DropRider(player: Player)
	local npc = loadedByPlayer[player]
	if not npc or npc.riders <= 1 then
		return
	end
	npc.riders -= 1
	local buddy = npc.model:FindFirstChild("Buddy")
	if buddy then
		buddy:Destroy()
	end
	local group = npc.group
	if group then
		group.Text = string.format(Config.Chaos.Carpool.Label, npc.riders)
		;(group.Parent :: BillboardGui).Enabled = npc.riders > 1
	end
end

-- Studio: a full carpool at a random free curb.
function PassengerService.DebugSpawnCarpool(): Npc?
	local free: { MapService.Point } = {}
	for _, point in MapService.GetPickups() do
		if not npcAtPickup[point.index] then
			table.insert(free, point)
		end
	end
	if #free == 0 then
		return nil
	end
	local point = free[rng:NextInteger(1, #free)]
	return PassengerService.SpawnAt(point, pickTier(VecUtil.FlatDistance(point.position, MapService.GetCenter())), false, Config.Chaos.Carpool.MaxRiders)
end

-- Studio: a ticking fare at a random free curb.
function PassengerService.DebugSpawnTicking(): Npc?
	local free: { MapService.Point } = {}
	for _, point in MapService.GetPickups() do
		if not npcAtPickup[point.index] then
			table.insert(free, point)
		end
	end
	if #free == 0 then
		return nil
	end
	local point = free[rng:NextInteger(1, #free)]
	return PassengerService.SpawnAt(point, pickTier(VecUtil.FlatDistance(point.position, MapService.GetCenter())), false, 1, true)
end

-- A Weirdo card's bonus fare (DropService) at a random free curb: the card's costume, Config.Cosmetics.Bonus.Tier,
-- and only `owner` can pick it up for HeadStartSeconds. Nil when every curb is taken.
function PassengerService.SpawnWeirdo(owner: Player, cardId: string): Npc?
	local bonus = Config.Cosmetics.Bonus
	local tierDef = Config.Fares.Tiers[bonus.Tier]
	if not Config.Cosmetics.Cards[cardId] or not tierDef then
		return nil
	end
	local free: { MapService.Point } = {}
	for _, point in MapService.GetPickups() do
		if not npcAtPickup[point.index] then
			table.insert(free, point)
		end
	end
	if #free == 0 then
		return nil
	end
	local point = free[rng:NextInteger(1, #free)]
	local id = nextId
	nextId += 1
	local groundY = MapService.GroundY(point.position, point.position.Y)
	local groundPos = Vector3.new(point.position.X, groundY, point.position.Z)
	local npc = {
		id = id,
		tier = bonus.Tier,
		kind = "Regular",
		golden = false,
		state = 0,
		pickupIndex = point.index,
		position = groundPos,
		hp = tierDef.Hp,
		maxHp = tierDef.Hp,
		riders = 1,
		ticking = false,
		card = cardId,
		reservedFor = owner,
		revealAt = workspace:GetServerTimeNow() + bonus.HeadStartSeconds,
	} :: any
	local model, torso, icon, bubble = buildModel(npc, groundPos, point.cframe.LookVector)
	npc.model = model
	npc.torso = torso
	npc.icon = icon
	npc.bubble = bubble
	local typed = npc :: Npc
	npcs[id] = typed
	npcAtPickup[point.index] = id
	return typed
end

-- Still another player's weirdo (their head start isn't over)?
function PassengerService.IsReservedFrom(npc: Npc, player: Player?): boolean
	local owner = npc.reservedFor
	return owner ~= nil and owner ~= player and workspace:GetServerTimeNow() < (npc.revealAt or 0)
end

-- Debug: a Golden Fare at a random free curb (nil when every curb is taken or one is already in play).
function PassengerService.SpawnGolden(): Npc?
	if goldenInPlay() then
		return nil
	end
	local free: { MapService.Point } = {}
	for _, point in MapService.GetPickups() do
		if not npcAtPickup[point.index] then
			table.insert(free, point)
		end
	end
	if #free == 0 then
		return nil
	end
	local point = free[rng:NextInteger(1, #free)]
	return PassengerService.SpawnAt(point, pickTier(VecUtil.FlatDistance(point.position, MapService.GetCenter())), true)
end

-- A player fare's marker at the curb: a gold ring at their feet and a TAXI! sign over them (the person is the fare).
local function buildPlayerMarker(npc: Npc, groundPos: Vector3, look: Vector3): (Model, BasePart, TextLabel, TextLabel)
	local cfg = Config.PlayerFare
	local model = Instance.new("Model")
	model.Name = "PlayerFare_" .. npc.id
	model:SetAttribute("NpcId", npc.id)
	model:SetAttribute("Tier", npc.tier)
	model:SetAttribute("PlayerFare", true)
	CollectionService:AddTag(model, Config.Tags.Npc)
	local torsoCf = standCFrame(groundPos, look)
	local torso = makePart("Torso", Vector3.new(1, 1, 1), torsoCf, cfg.Color, model)
	torso.Anchored = true
	torso.Transparency = 1
	model.PrimaryPart = torso
	local ring = makePart("Ring", Vector3.new(0.3, cfg.RingRadius * 2, cfg.RingRadius * 2), torsoCf * CFrame.new(0, -2.4, 0) * CFrame.Angles(0, 0, math.pi / 2), cfg.Color, model)
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.Anchored = true
	local icon = makeLabel(torso, "Icon", UDim2.fromOffset(110, 40), Vector3.new(0, 5, 0))
	icon.Text = cfg.Label
	icon.TextColor3 = cfg.Color
	local bubble = makeLabel(torso, "Bubble", UDim2.fromOffset(200, 34), Vector3.new(0, 7.5, 0))
	bubble.Text = ""
	;(bubble.Parent :: BillboardGui).Enabled = false
	model.Parent = folder
	return model, torso, icon, bubble
end

-- Player fares waiting or riding right now.
function PassengerService.CountPlayerFares(): number
	local n = 0
	for _, npc in npcs do
		if npc.rider then
			n += 1
		end
	end
	return n
end

-- This person's fare (waiting at the curb or riding), if they hailed.
function PassengerService.GetRiderFare(rider: Player): Npc?
	for _, npc in npcs do
		if npc.rider == rider then
			return npc
		end
	end
	return nil
end

-- A person hails: a fare at `spot` (on the curb, facing the road) with the tier its distance from the start gives,
-- picked up like any passenger (bots too). nil when MaxOnBoard player fares are already out, or they already hailed.
function PassengerService.SpawnPlayerFare(rider: Player, spot: Vector3, look: Vector3): Npc?
	if PassengerService.CountPlayerFares() >= Config.PlayerFare.MaxOnBoard or PassengerService.GetRiderFare(rider) then
		return nil
	end
	local tier = pickTier(VecUtil.FlatDistance(spot, MapService.GetCenter()))
	local tierDef = Config.Fares.Tiers[tier]
	local id = nextId
	nextId += 1
	local groundPos = Vector3.new(spot.X, MapService.GroundY(spot, spot.Y), spot.Z)
	local npc = {
		id = id,
		tier = tier,
		kind = "Regular",
		golden = false,
		state = 0,
		pickupIndex = 0, -- not standing at a pickup point
		position = groundPos,
		hp = tierDef.Hp,
		maxHp = tierDef.Hp,
		riders = 1,
		ticking = false,
		rider = rider,
	} :: any
	local model, torso, icon, bubble = buildPlayerMarker(npc, groundPos, look)
	npc.model = model
	npc.torso = torso
	npc.icon = icon
	npc.bubble = bubble
	local typed = npc :: Npc
	npcs[id] = typed
	return typed
end

-- The person called their hail off (walked away, tapped CANCEL, or a seat opened): only while nobody has picked them up.
function PassengerService.CancelHail(rider: Player, reason: string)
	local npc = PassengerService.GetRiderFare(rider)
	if npc and npc.state == 0 then
		freeRider(npc, nil, reason)
		destroyNpc(npc)
	end
end

-- Round over: people riding along step out beside their cab, and open hails are called off.
function PassengerService.EndRides()
	for driver, npc in loadedByPlayer do
		if npc.rider then
			unload(driver)
			freeRider(npc, driver, "roundover")
			destroyNpc(npc)
		end
	end
	for _, npc in npcs do
		if npc.rider and npc.state == 0 then
			freeRider(npc, nil, "cleared")
			destroyNpc(npc)
		end
	end
end

-- Which tiers are currently on the board (available or walking back).
local function tiersOnBoard(): { [string]: boolean }
	local present: { [string]: boolean } = {}
	for _, npc in npcs do
		if (npc.state == 0 or npc.state == 2) and not npc.rider then
			present[npc.tier] = true
		end
	end
	return present
end

-- Spawn one NPC at a random free pickup point with distance-weighted tier. nil when every point is taken.
-- With GuaranteeEachTier, a missing tier is forced onto the curb that suits it (red far out, green near the start).
function PassengerService.SpawnWeighted(): Npc?
	local free: { MapService.Point } = {}
	for _, point in MapService.GetPickups() do
		if not npcAtPickup[point.index] then
			table.insert(free, point)
		end
	end
	if #free == 0 then
		return nil
	end
	local center = MapService.GetCenter()
	if Config.Fares.GuaranteeEachTier and PassengerService.CountOnBoard() >= 2 then
		local present = tiersOnBoard()
		local bands = Config.Fares.TierWeightsByDistance
		if not present.Red then
			-- farthest free curb
			table.sort(free, function(a, b)
				return VecUtil.FlatDistance(a.position, center) > VecUtil.FlatDistance(b.position, center)
			end)
			return PassengerService.SpawnAt(free[1], "Red")
		elseif not present.Green then
			table.sort(free, function(a, b)
				return VecUtil.FlatDistance(a.position, center) < VecUtil.FlatDistance(b.position, center)
			end)
			return PassengerService.SpawnAt(free[1], "Green")
		elseif not present.Yellow then
			local mid = bands[1].MaxDistance
			table.sort(free, function(a, b)
				return math.abs(VecUtil.FlatDistance(a.position, center) - mid) < math.abs(VecUtil.FlatDistance(b.position, center) - mid)
			end)
			return PassengerService.SpawnAt(free[1], "Yellow")
		end
	end
	local point = free[rng:NextInteger(1, #free)]
	local tier = pickTier(VecUtil.FlatDistance(point.position, center))
	return PassengerService.SpawnAt(point, tier)
end

-- NPCs waiting or walking back (player fares are extra: they never count against the board).
function PassengerService.CountOnBoard(): number
	local n = 0
	for _, npc in npcs do
		if (npc.state == 0 or npc.state == 2) and not npc.rider then
			n += 1
		end
	end
	return n
end

function PassengerService.EnsureCount(target: number)
	local guard = 0
	while PassengerService.CountOnBoard() < target and guard < 64 do
		guard += 1
		if not PassengerService.SpawnWeighted() then
			break
		end
	end
end

-- `player`: the cab asking (another player's weirdo in its head start is skipped).
function PassengerService.GetAvailableNear(position: Vector3, radius: number, player: Player?): (Npc?, number)
	local best: Npc? = nil
	local bestDist = radius
	for _, npc in npcs do
		if npc.state == 0 and not PassengerService.IsReservedFrom(npc, player) then
			local d = VecUtil.FlatDistance(npc.position, position)
			if d <= bestDist then
				bestDist = d
				best = npc
			end
		end
	end
	return best, bestDist
end

function PassengerService.Get(id: number): Npc?
	return npcs[id]
end

function PassengerService.GetAll(): { [number]: Npc }
	return npcs
end

-- Passengers walking back who are out in the road right now (not on a block), so traffic can stop for them.
function PassengerService.GetWalkersInRoad(): { Vector3 }
	local B = MapService.GetBlockout()
	local half = B.CellSize / 2
	local list: { Vector3 } = {}
	for _, npc in npcs do
		if npc.state ~= 2 then
			continue
		end
		local p = npc.torso.Position
		local onBlock = false
		for _, cx in B.CellCenters do
			for _, cz in B.CellCenters do
				if math.abs(p.X - cx) < half and math.abs(p.Z - cz) < half then
					onBlock = true
				end
			end
		end
		if not onBlock then
			table.insert(list, Vector3.new(p.X, 0, p.Z))
		end
	end
	return list
end

function PassengerService.GetLoaded(player: Player): Npc?
	return loadedByPlayer[player]
end

function PassengerService.Board(npc: Npc, player: Player)
	if npc.state ~= 0 or loadedByPlayer[player] then
		return
	end
	if npcAtPickup[npc.pickupIndex] == npc.id then
		npcAtPickup[npc.pickupIndex] = nil
	end
	npc.state = 1
	npc.boardedBy = player
	local entry = VehicleService.GetEntry(player)
	local stats = if entry then Config.Vehicles.Stats[entry.vehicleId] else nil
	npc.maxHp = Config.Fares.Tiers[npc.tier].Hp + (if stats and stats.PassengerHpBonus then stats.PassengerHpBonus else 0)
	npc.hp = npc.maxHp
	loadedByPlayer[player] = npc
	lastDamageAt[player] = nil
	npc.model.Parent = nil
	local rider = npc.rider
	if rider then
		rider:SetAttribute("RidingWith", player.UserId) -- every client seats them in this cab
	end
	onBoarded:Fire(player, npc)
end

-- Seatbelt: passenger ignores all damage until this server time.
function PassengerService.SetImmune(player: Player, seconds: number)
	immuneUntil[player] = workspace:GetServerTimeNow() + seconds
end

function PassengerService.IsImmune(player: Player): boolean
	local until_ = immuneUntil[player]
	return until_ ~= nil and workspace:GetServerTimeNow() < until_
end

-- Damage from any outside source. Respects the per-player cooldown and Seatbelt immunity.
-- `attacker` is the rival who caused it (nil for crashes); a bail it causes pays them the Hunter Bonus.
function PassengerService.ApplyDamage(player: Player, amount: number, source: string, attacker: Player?): number
	local npc = loadedByPlayer[player]
	if not npc or amount <= 0 then
		return 0
	end
	if PassengerService.IsImmune(player) then
		return 0
	end
	local now = workspace:GetServerTimeNow()
	local last = lastDamageAt[player]
	if last and now - last < Config.Passenger.DamageCooldown then
		return 0
	end
	lastDamageAt[player] = now
	if attacker then
		lastAttacker[player] = attacker
	end
	local armor = player:GetAttribute("Pit_ArmoredSeats")
	if typeof(armor) == "number" then
		amount *= armor
	end
	if MonetizationService.HasPass(player, "ArmoredSeats") then
		amount *= Config.Monetization.ArmoredSeatsDamageMult -- the Robux pass, on top of the Pit Stop card
	end
	local entry = VehicleService.GetEntry(player)
	local stats = if entry then Config.Vehicles.Stats[entry.vehicleId] else nil
	if stats and stats.PassengerDamageMult then
		amount *= stats.PassengerDamageMult
	end
	if source == "crash" then
		local kindDef = Config.PassengerTypes.Kinds[npc.kind]
		amount *= if kindDef then kindDef.CrashMult else 1 -- Nervous passengers feel every bump
	end
	amount = math.min(amount, npc.hp) -- report what was actually lost (a Tomato hit is far more than any HP)
	npc.hp = math.max(0, npc.hp - amount)
	onDamaged:Fire(player, amount, source)
	if npc.hp <= 0 then
		PassengerService.Bail(player, "hp")
	end
	return amount
end

-- The cost of firing an attack item while loaded. Ignores the cooldown and does not start one.
function PassengerService.ApplySelfCost(player: Player)
	local npc = loadedByPlayer[player]
	if not npc or PassengerService.IsImmune(player) then
		return
	end
	lastAttacker[player] = nil
	npc.hp = math.max(0, npc.hp - Config.Passenger.SelfHitCost)
	onDamaged:Fire(player, Config.Passenger.SelfHitCost, "self")
	if npc.hp <= 0 then
		PassengerService.Bail(player, "hp")
	end
end

-- Passenger gets out angry, walks to the nearest free pickup point, becomes available again with the same destination.
function PassengerService.Bail(player: Player, reason: string)
	local attacker = if reason == "hp" then lastAttacker[player] else nil -- read before unload clears it
	local npc = unload(player)
	if not npc then
		return
	end
	if npc.rider then
		-- a person bails: tossed out beside the cab, the fare is over (no walking back to a curb)
		onBailed:Fire(player, npc, reason, attacker)
		freeRider(npc, player, reason)
		destroyNpc(npc)
		return
	end
	local exitPos, look = exitPose(player, npc.position)
	npc.position = exitPos
	npc.torso.CFrame = standCFrame(exitPos, look)
	npc.model.Parent = folder
	showBubble(npc, if reason == "timeout" then "TIME'S UP, I'M OUT" else randomLine(Config.Passenger.AngryLines), Config.Passenger.BailBubbleSeconds)
	local occupied: { [number]: boolean } = {}
	for index in npcAtPickup do
		occupied[index] = true
	end
	local point = MapService.NearestPickup(exitPos, occupied)
	onBailed:Fire(player, npc, reason, attacker)
	if point then
		walkTo(npc, point)
	else
		npc.state = 0
	end
end

-- Passenger delivered: steps out, says thanks, despawns. Returns the NPC for stats.
function PassengerService.Deliver(player: Player): Npc?
	local npc = unload(player)
	if not npc then
		return nil
	end
	if npc.rider then
		freeRider(npc, player, "delivered")
		destroyNpc(npc)
		return npc
	end
	local exitPos, look = exitPose(player, npc.position)
	npc.position = exitPos
	npc.state = 3
	npc.torso.CFrame = standCFrame(exitPos, look)
	local beam = npc.model:FindFirstChild("GoldenBeam")
	if beam then
		beam:Destroy() -- a delivered Golden Fare is spent: no pillar to lure rivals while it says thanks
	end
	npc.model.Parent = folder
	showBubble(npc, randomLine(Config.Passenger.ThanksLines), Config.Fares.ThanksSeconds)
	task.delay(Config.Fares.ThanksSeconds, function()
		destroyNpc(npc)
	end)
	return npc
end

-- Player left or was reset: put the passenger straight back on the board.
function PassengerService.Release(player: Player)
	local npc = unload(player)
	if not npc then
		return
	end
	if npc.rider then
		freeRider(npc, player, "released")
		destroyNpc(npc)
		return
	end
	local occupied: { [number]: boolean } = {}
	for index in npcAtPickup do
		occupied[index] = true
	end
	local point = MapService.NearestPickup(npc.position, occupied)
	if not point then
		destroyNpc(npc)
		return
	end
	npc.pickupIndex = point.index
	npcAtPickup[point.index] = npc.id
	local groundY = MapService.GroundY(point.position, point.position.Y)
	npc.position = Vector3.new(point.position.X, groundY, point.position.Z)
	npc.torso.CFrame = standCFrame(npc.position, point.cframe.LookVector)
	npc.state = 0
	npc.model.Parent = folder
end

function PassengerService.SetHp(player: Player, hp: number)
	local npc = loadedByPlayer[player]
	if npc then
		npc.hp = math.clamp(hp, 0, npc.maxHp)
		if npc.hp <= 0 then
			PassengerService.Bail(player, "hp")
		end
	end
end

function PassengerService.ClearAll()
	for _, npc in npcs do
		if npc.walkTween then
			npc.walkTween:Cancel()
		end
		freeRider(npc, npc.boardedBy, "cleared")
		npc.model:Destroy()
	end
	table.clear(npcs)
	table.clear(npcAtPickup)
	for player, npc in loadedByPlayer do
		onUnloaded:Fire(player, npc)
	end
	table.clear(loadedByPlayer)
	table.clear(lastDamageAt)
	table.clear(immuneUntil)
	table.clear(lastAttacker)
end

function PassengerService.Snapshot(): { Types.NpcSnap }
	local list: { Types.NpcSnap } = {}
	for _, npc in npcs do
		if npc.state ~= 1 then
			local pos = if npc.state == 2 then npc.torso.Position else npc.position
			table.insert(list, {
				id = npc.id,
				x = math.round(pos.X * 10) / 10,
				z = math.round(pos.Z * 10) / 10,
				tier = npc.tier :: string,
				state = npc.state,
				kind = npc.kind,
				golden = npc.golden,
				riders = npc.riders,
				ticking = npc.ticking,
				player = if npc.rider then true else nil,
				card = npc.card,
				owner = if npc.reservedFor then npc.reservedFor.UserId else nil,
				revealAt = if npc.reservedFor then npc.revealAt else nil,
			})
		end
	end
	return list
end

function PassengerService.Init()
	folder = MapService.GetRuntimeFolder("NPCs")

	-- Crash damage: how much of the car's top speed the hit took decides what share of the trip's base HP it costs.
	VehicleService.OnCrash:Connect(function(player: Player, lost: number)
		local npc = loadedByPlayer[player]
		if not npc then
			return
		end
		local cfg = Config.Passenger
		local intensity = VehicleService.CrashIntensity(player, lost)
		if intensity < cfg.CrashMinIntensity then
			return
		end
		local t = math.clamp((intensity - cfg.CrashMinIntensity) / (cfg.CrashFullIntensity - cfg.CrashMinIntensity), 0, 1)
		local share = cfg.CrashMinShare + (1 - cfg.CrashMinShare) * t
		PassengerService.ApplyDamage(player, share * Config.Fares.Tiers[npc.tier].Hp, "crash")
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		-- a person who hailed left: their curb is empty, or their driver's fare is over
		local fare = PassengerService.GetRiderFare(player)
		if fare then
			local driver = fare.boardedBy
			if fare.state == 1 and driver then
				PassengerService.Bail(driver, "left")
			else
				PassengerService.CancelHail(player, "left")
			end
		end
		PassengerService.Release(player)
		lastDamageAt[player] = nil
		immuneUntil[player] = nil
		lastAttacker[player] = nil
		for victim, attacker in lastAttacker do
			if attacker == player then
				lastAttacker[victim] = nil
			end
		end
	end)
end

function PassengerService.Start() end

return PassengerService
