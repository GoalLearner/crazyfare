--!strict
-- NPC passengers: spawning by tier weighting, boarding, HP (damage and crashes; no regen), bailing and walking back,
-- delivery thanks. FareService owns the money side and listens to OnBailed.

local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)

export type Npc = {
	id: number,
	model: Model,
	torso: BasePart,
	tier: string,
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
}

local PassengerService = {}

local onBailed: Signal.Signal<Player, Npc, string, Player?> = Signal.new()
local onDamaged: Signal.Signal<Player, number, string> = Signal.new()
PassengerService.OnBailed = onBailed -- (victim, npc, reason "hp" | "timeout", attacker when a rival caused it)
PassengerService.OnDamaged = onDamaged -- (player, amount, source)

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

local function buildModel(npc: Npc, groundPos: Vector3, look: Vector3): (Model, BasePart, TextLabel, TextLabel)
	local tierDef = Config.Fares.Tiers[npc.tier]
	local model = Instance.new("Model")
	model.Name = "NPC_" .. npc.id
	model:SetAttribute("NpcId", npc.id)
	model:SetAttribute("Tier", npc.tier)
	CollectionService:AddTag(model, Config.Tags.Npc)

	local torsoCf = standCFrame(groundPos, look)
	local torso = makePart("Torso", Vector3.new(1.6, 1.8, 0.9), torsoCf, tierDef.Color, model)
	torso.Anchored = true
	model.PrimaryPart = torso

	local head = makePart("Head", Vector3.new(1.1, 1.1, 1.1), torsoCf * CFrame.new(0, 1.45, 0), SKIN, model)
	head.Shape = Enum.PartType.Ball
	weld(torso, head)
	for _, side in { -1, 1 } do
		local leg = makePart("Leg", Vector3.new(0.7, 1.6, 0.7), torsoCf * CFrame.new(0.45 * side, -1.7, 0), PANTS, model)
		weld(torso, leg)
		local arm = makePart("Arm", Vector3.new(0.5, 1.5, 0.5), torsoCf * CFrame.new(1.05 * side, 0.1, 0), tierDef.Color, model)
		weld(torso, arm)
	end

	local icon = makeLabel(head, "Icon", UDim2.fromOffset(46, 46), Vector3.new(0, 1.6, 0))
	icon.Text = "$"
	icon.TextColor3 = tierDef.Color
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
	stroke.Color = tierDef.Color
	stroke.Parent = ring
	icon.ZIndex = 2

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
	VehicleService.SetSilhouette(player, false)
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

function PassengerService.SpawnAt(point: MapService.Point, tier: string): Npc
	local tierDef = Config.Fares.Tiers[tier]
	local id = nextId
	nextId += 1
	local groundY = MapService.GroundY(point.position, point.position.Y)
	local groundPos = Vector3.new(point.position.X, groundY, point.position.Z)
	local npc = {
		id = id,
		tier = tier,
		state = 0,
		pickupIndex = point.index,
		position = groundPos,
		hp = tierDef.Hp,
		maxHp = tierDef.Hp,
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

-- Which tiers are currently on the board (available or walking back).
local function tiersOnBoard(): { [string]: boolean }
	local present: { [string]: boolean } = {}
	for _, npc in npcs do
		if npc.state == 0 or npc.state == 2 then
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

function PassengerService.CountOnBoard(): number
	local n = 0
	for _, npc in npcs do
		if npc.state == 0 or npc.state == 2 then
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

function PassengerService.GetAvailableNear(position: Vector3, radius: number): (Npc?, number)
	local best: Npc? = nil
	local bestDist = radius
	for _, npc in npcs do
		if npc.state == 0 then
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
	VehicleService.SetSilhouette(player, true)
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
	local entry = VehicleService.GetEntry(player)
	local stats = if entry then Config.Vehicles.Stats[entry.vehicleId] else nil
	if stats and stats.PassengerDamageMult then
		amount *= stats.PassengerDamageMult
	end
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
	local npc = unload(player)
	if not npc then
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
	local attacker = if reason == "hp" then lastAttacker[player] else nil
	lastAttacker[player] = nil
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
	local exitPos, look = exitPose(player, npc.position)
	npc.position = exitPos
	npc.state = 3
	npc.torso.CFrame = standCFrame(exitPos, look)
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
		npc.model:Destroy()
	end
	table.clear(npcs)
	table.clear(npcAtPickup)
	for player in loadedByPlayer do
		VehicleService.SetSilhouette(player, false)
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
			})
		end
	end
	return list
end

function PassengerService.Init()
	folder = MapService.GetRuntimeFolder("NPCs")

	VehicleService.OnCrash:Connect(function(player: Player, delta: number)
		local damage = math.min(Config.Passenger.CrashDamageMax, (delta - Config.Passenger.CrashDeltaThreshold) * Config.Passenger.CrashDamagePerStud)
		if damage >= 1 then
			PassengerService.ApplyDamage(player, damage, "crash")
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		PassengerService.Release(player)
		lastDamageAt[player] = nil
	end)
end

function PassengerService.Start() end

return PassengerService
