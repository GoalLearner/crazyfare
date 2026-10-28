--!strict
-- Item boxes and fruit stands, the one-slot inventory, rank-weighted rolls, and every item's server-side effect:
-- Tomato (homing projectile), Banana + OilSlick (traps), LemonNitro (boost), Shield + Seatbelt (defense).
-- Projectiles also knock tagged props. Clients only render what they are told.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local PassengerService = require(script.Parent.PassengerService)
local Racers = require(script.Parent.Parent.Racers)
local FareService = require(script.Parent.FareService)
local MonetizationService = require(script.Parent.MonetizationService)

type Box = { part: BasePart, activeAt: number }
type Stand = { model: Model, pivot: CFrame, activeAt: number } -- a fruit stall; activeAt > 0 while it's smashed
type Projectile = {
	part: Part,
	owner: Player,
	target: Player?,
	position: Vector3,
	direction: Vector3,
	diesAt: number,
}
type Trap = {
	part: Part,
	owner: Player,
	kind: string,
	position: Vector3,
	triggerRadius: number,
	armedForOwnerAt: number,
	diesAt: number,
}

local ItemService = {}

local onTomatoHit: Signal.Signal<Player, Player> = Signal.new()
ItemService.OnTomatoHit = onTomatoHit -- (attacker, victim) on a landed splat
local onSmash: Signal.Signal<Player> = Signal.new()
ItemService.OnSmash = onSmash -- (driver) drove through a fruit stand

local held: { [Player]: string } = {}
local spare: { [Player]: { string } } = {} -- items waiting behind the held one (the Double Item pass), in order
local shieldHits: { [Player]: number } = {} -- hits a player's shield can still absorb
local boxRespawn: number? = nil -- Frenzy: boxes come back this fast
local boxes: { Box } = {}
local stands: { Stand } = {}
local projectiles: { Projectile } = {}
local traps: { Trap } = {}
local enabled = false
local rng = Random.new()
local folder: Folder
local itemEvent: RemoteEvent

local function fire(player: Player, payload: Types.ItemEventPayload)
	if Racers.IsBot(player) then
		return -- bots have no client; BotService reads their spinouts and boosts from the car entry
	end
	itemEvent:FireClient(player, payload)
end

local function broadcast(payload: Types.ItemEventPayload)
	itemEvent:FireAllClients(payload)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- A mesh template from ReplicatedStorage.ItemModels (imported art), or nil to fall back to parts.
local function itemTemplate(name: string): Model?
	local models = ReplicatedStorage:FindFirstChild("ItemModels")
	local template = if models then models:FindFirstChild(name) else nil
	return if template and template:IsA("Model") and template.PrimaryPart then template else nil
end

-- Clone a template, make it inert (anchored, no collisions), scale its longest side to `size`, pivot it to `cf`.
local function placeTemplate(template: Model, cf: CFrame, size: number): Model
	local clone = template:Clone()
	local _, bounds = clone:GetBoundingBox()
	local longest = math.max(bounds.X, bounds.Y, bounds.Z, 0.01)
	clone:ScaleTo(clone:GetScale() * size / longest)
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	clone:PivotTo(cf)
	return clone
end

local function roll(bucket: Types.RankBucket): string
	local weights = Config.Items.RankWeights[bucket] or Config.Items.RankWeights.Mid
	local total = 0
	for id in Config.Items.Pool do
		total += weights[id] or 0
	end
	local r = rng:NextNumber() * total
	local acc = 0
	for id in Config.Items.Pool do
		acc += weights[id] or 0
		if r <= acc then
			return id
		end
	end
	return "Tomato"
end

function ItemService.GetHeld(player: Player): string
	return held[player] or ""
end

-- Items waiting behind the held one.
local function spareCount(player: Player): number
	local list = spare[player]
	return if list then #list else 0
end

function ItemService.GetSpareCount(player: Player): number
	return spareCount(player)
end

-- Room for one more from a box or a stand: one slot, two with the Double Item pass.
local function hasRoom(player: Player): boolean
	local slots = if MonetizationService.HasPass(player, "DoubleItem") then Config.Monetization.DoubleItemSlots else 1
	local count = (if held[player] then 1 else 0) + spareCount(player)
	return count < slots
end

-- Into the slot if it's empty, else into the queue behind it; tells the client what it holds and how many wait.
local function addItem(player: Player, item: string)
	if not held[player] then
		held[player] = item
	else
		local list = spare[player] or {}
		table.insert(list, item)
		spare[player] = list
	end
	fire(player, { kind = "Granted", item = held[player], count = spareCount(player) })
end


function ItemService.HasShield(player: Player): boolean
	return (shieldHits[player] or 0) > 0
end

function ItemService.Give(player: Player, item: string)
	if not Config.Items.Pool[item] then
		return
	end
	held[player] = item
	fire(player, { kind = "Granted", item = item, count = spareCount(player) })
end

function ItemService.SetEnabled(value: boolean)
	enabled = value
end

local function setBoxActive(box: Box, active: boolean)
	box.part:SetAttribute("Active", active)
end

-- `dir`: the smasher's heading, so every client throws the fruit the way they were going.
local function setStandActive(stand: Stand, active: boolean, dir: Vector3?)
	if dir then
		stand.model:SetAttribute("SmashDir", dir)
	end
	stand.model:SetAttribute("Active", active)
end

-- Bananas and Oil Slicks on the road (bots hop over them).
function ItemService.GetTraps(): { { position: Vector3, radius: number } }
	local list: { { position: Vector3, radius: number } } = {}
	for _, trap in traps do
		table.insert(list, { position = trap.position, radius = trap.triggerRadius })
	end
	return list
end

-- The fruit stalls still standing (bots swerve for them; Studio's "To stand" lines up on one).
function ItemService.GetActiveStands(): { CFrame }
	local list: { CFrame } = {}
	for _, stand in stands do
		if stand.activeAt == 0 then
			table.insert(list, stand.pivot)
		end
	end
	return list
end

-- A built-in shield (the Phantom: Config.Vehicles.Stats.<Id>.BuiltInShield) that is charged now takes the hit and
-- starts recharging; the ready time is a player attribute every client reads for the bubble.
local function consumeBuiltInShield(victim: Player, position: Vector3): boolean
	local entry = VehicleService.GetEntry(victim)
	local stats = if entry then Config.Vehicles.Stats[entry.vehicleId] else nil
	if not stats or not stats.BuiltInShield then
		return false
	end
	local p = Config.Vehicles.Phantom
	local readyAt = victim:GetAttribute(p.ShieldAttribute)
	if typeof(readyAt) == "number" and now() < readyAt then
		return false
	end
	victim:SetAttribute(p.ShieldAttribute, now() + p.ShieldRecharge)
	fire(victim, { kind = "ShieldBreak", item = "Shield" })
	broadcast({ kind = "Burst", item = "Shield", position = position })
	return true
end

-- Returns true when a shield absorbed the hit (and tells the victim). `source` "Tomato" or "ram": a charged built-in
-- shield takes it when there's no Shield item up (pedestrians and traps get past it).
local function consumeShield(victim: Player, position: Vector3, source: string?): boolean
	local left = shieldHits[victim] or 0
	if left <= 0 then
		return (source == "Tomato" or source == "ram") and consumeBuiltInShield(victim, position)
	end
	left -= 1
	if left > 0 then
		shieldHits[victim] = left
	else
		shieldHits[victim] = nil
	end
	if left <= 0 then
		VehicleService.SetHighlight(victim, nil, 0)
	end
	fire(victim, { kind = "ShieldBreak", item = "Shield" })
	broadcast({ kind = "Burst", item = "Shield", position = position })
	return true
end

-- Frenzy: item boxes respawn in `seconds` (nil = the normal Config.Items.BoxRespawnSeconds); boxes already waiting
-- come back that soon too.
function ItemService.SetBoxRespawn(seconds: number?)
	boxRespawn = seconds
	if seconds then
		local soon = workspace:GetServerTimeNow() + seconds
		for _, box in boxes do
			if box.activeAt > soon then
				box.activeAt = soon
			end
		end
	end
end

-- A non-item hit a raised Shield can take instead of the passenger (`source` "ram" also lets a built-in shield take
-- it; a pedestrian clip passes nothing). True when it did.
function ItemService.AbsorbHit(victim: Player, position: Vector3, source: string?): boolean
	return consumeShield(victim, position, source)
end

-- Nearest rival inside LockRange; a loaded rival wins over an empty one at any distance.
local function pickTarget(owner: Player, from: Vector3): Player?
	local best: Player? = nil
	local bestDist = Config.Items.Tomato.LockRange
	local bestLoaded = false
	for player, entry in VehicleService.GetAll() do
		if player == owner or entry.chassis.Anchored then
			continue
		end
		local d = (entry.chassis.Position - from).Magnitude
		if d > Config.Items.Tomato.LockRange then
			continue
		end
		local loaded = PassengerService.GetLoaded(player) ~= nil
		if (loaded and not bestLoaded) or (loaded == bestLoaded and d < bestDist) then
			best = player
			bestDist = d
			bestLoaded = loaded
		end
	end
	return best
end

local function makeProjectilePart(name: string, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.8, 1.8, 1.8)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	CollectionService:AddTag(part, Config.Tags.Projectile)
	return part
end

local function launchTomato(owner: Player, entry: VehicleService.VehicleEntry)
	local cfg = Config.Items.Tomato
	local muzzle = entry.chassis:FindFirstChild("Muzzle")
	local origin = if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else entry.chassis.Position
	origin += Vector3.new(0, cfg.LaunchHeight, 0)
	local direction = VecUtil.FlatUnit(entry.chassis.CFrame.LookVector)
	local target = pickTarget(owner, origin)
	if target then
		local targetPos = VehicleService.GetPosition(target)
		if targetPos then
			direction = (targetPos - origin).Unit
		end
	end

	local part = makeProjectilePart("Tomato", Config.Items.Pool.Tomato.Color)
	part.CFrame = CFrame.lookAt(origin, origin + direction)
	local template = itemTemplate("Tomato")
	if template then
		part.Transparency = 1
		local visual = placeTemplate(template, part.CFrame, 2.2)
		for _, piece in visual:GetDescendants() do
			if piece:IsA("BasePart") then
				piece.Anchored = false
				piece.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = part
				weld.Part1 = piece
				weld.Parent = piece
			end
		end
		visual.Parent = part
	end
	part:SetAttribute("OwnerUserId", owner.UserId)
	part.Parent = folder

	table.insert(projectiles, {
		part = part,
		owner = owner,
		target = target,
		position = origin,
		direction = direction,
		diesAt = now() + cfg.Lifetime,
	})
end

-- Ground position a few studs behind the rear bumper.
local function behindCar(entry: VehicleService.VehicleEntry, dropBack: number): Vector3
	local behind = (entry.chassis.CFrame * CFrame.new(0, 0, 5.5 + dropBack)).Position
	local groundY = MapService.GroundY(behind, entry.chassis.Position.Y - 2)
	return Vector3.new(behind.X, groundY, behind.Z)
end

local function placeTrap(owner: Player, kind: string, part: Part, position: Vector3, triggerRadius: number, ownerImmunity: number, lifetime: number)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part:SetAttribute("OwnerUserId", owner.UserId)
	part:SetAttribute("TrapKind", kind)
	CollectionService:AddTag(part, Config.Tags.Trap)
	part.Parent = folder
	print(string.format("[ItemService] %s placed at %.0f, %.0f, %.0f", kind, position.X, position.Y, position.Z))
	table.insert(traps, {
		part = part,
		owner = owner,
		kind = kind,
		position = position,
		triggerRadius = triggerRadius,
		armedForOwnerAt = now() + ownerImmunity,
		diesAt = now() + lifetime,
	})
end

-- A crescent: three short segments bent along an arc, brown tips, all welded to the middle one.
local function buildBananaShape(root: CFrame): Part
	local color = Config.Items.Pool.Banana.Color
	local tip = Color3.fromRGB(90, 60, 30)
	local function segment(name: string, length: number, c: Color3, offset: CFrame, parent: Part?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(length, 0.7, 0.7)
		p.Color = c
		p.Material = Enum.Material.SmoothPlastic
		p.CFrame = root * offset
		p.Anchored = parent == nil
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		if parent then
			local w = Instance.new("Weld")
			w.Part0 = parent
			w.Part1 = p
			w.C0 = parent.CFrame:ToObjectSpace(p.CFrame)
			w.Parent = p
			p.Parent = parent
		end
		return p
	end
	local bend = math.rad(28)
	local mid = segment("Banana", 1.2, color, CFrame.new(0, 0.4, 0))
	segment("Left", 1.2, color, CFrame.new(-1.1, 0.62, 0) * CFrame.Angles(0, 0, bend), mid)
	segment("Right", 1.2, color, CFrame.new(1.1, 0.62, 0) * CFrame.Angles(0, 0, -bend), mid)
	segment("TipL", 0.45, tip, CFrame.new(-1.8, 0.98, 0) * CFrame.Angles(0, 0, bend * 1.6), mid)
	segment("TipR", 0.45, tip, CFrame.new(1.8, 0.98, 0) * CFrame.Angles(0, 0, -bend * 1.6), mid)
	return mid
end

local function dropBanana(owner: Player, entry: VehicleService.VehicleEntry)
	local cfg = Config.Items.Banana
	local ground = behindCar(entry, cfg.DropBack)
	local position = ground + Vector3.new(0, 0.5, 0)
	local root = CFrame.new(ground) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local template = itemTemplate("Banana")
	local part: Part
	if template then
		local visual = placeTemplate(template, root * CFrame.new(0, 0.9, 0), 3.6)
		part = visual.PrimaryPart :: Part
		visual.Parent = folder
	else
		part = buildBananaShape(root)
	end
	placeTrap(owner, "Banana", part, position, cfg.TriggerRadius, cfg.OwnerImmunity, cfg.Lifetime)
end

local function dropOil(owner: Player, entry: VehicleService.VehicleEntry)
	local cfg = Config.Items.OilSlick
	local ground = behindCar(entry, cfg.DropBack)
	local position = ground + Vector3.new(0, 0.15, 0)
	local part = Instance.new("Part")
	part.Name = "OilSlick"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.2, cfg.TriggerRadius * 2, cfg.TriggerRadius * 2)
	part.Color = Config.Items.Pool.OilSlick.Color
	part.Material = Enum.Material.Glass
	part.Transparency = cfg.Transparency
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	placeTrap(owner, "OilSlick", part, position, cfg.TriggerRadius, cfg.OwnerImmunity, cfg.Lifetime)
end

local function applyBoost(player: Player, entry: VehicleService.VehicleEntry)
	local cfg = Config.Items.LemonNitro
	entry.boostUntil = now() + cfg.Seconds
	fire(player, { kind = "Boost", item = "LemonNitro", seconds = cfg.Seconds })
end

local function raiseShield(player: Player)
	shieldHits[player] = Config.Items.Shield.Blocks
	VehicleService.SetHighlight(player, Config.Items.Pool.Shield.Color, 0)
	fire(player, { kind = "ShieldUp", item = "Shield" })
end

local function buckleSeatbelt(player: Player)
	local cfg = Config.Items.Seatbelt
	PassengerService.SetImmune(player, cfg.Seconds)
	VehicleService.SetHighlight(player, Config.Items.Pool.Seatbelt.Color, cfg.Seconds)
	fire(player, { kind = "Seatbelt", item = "Seatbelt", seconds = cfg.Seconds })
end

function ItemService.Use(player: Player)
	if not enabled then
		return
	end
	local item = held[player]
	if not item then
		return
	end
	local entry = VehicleService.GetEntry(player)
	if not entry or entry.chassis.Anchored then
		return
	end
	held[player] = nil
	fire(player, { kind = "Used", item = item })
	-- the next one in line moves up into the slot
	local list = spare[player]
	local nextItem = if list then table.remove(list, 1) else nil
	if list and nextItem then
		held[player] = nextItem
		fire(player, { kind = "Granted", item = nextItem, count = #list })
	end
	print(string.format("[ItemService] %s used %s", player.Name, item))

	if Config.Items.SelfCostItems[item] then
		PassengerService.ApplySelfCost(player)
	end

	if item == "Tomato" then
		launchTomato(player, entry)
	elseif item == "Banana" then
		dropBanana(player, entry)
	elseif item == "OilSlick" then
		dropOil(player, entry)
	elseif item == "LemonNitro" then
		applyBoost(player, entry)
	elseif item == "Shield" then
		raiseShield(player)
	elseif item == "Seatbelt" then
		buckleSeatbelt(player)
	end
end

local function hitWithTomato(projectile: Projectile, victim: Player, victimEntry: VehicleService.VehicleEntry)
	local cfg = Config.Items.Tomato
	local at = victimEntry.chassis.Position
	if consumeShield(victim, at, "Tomato") then
		fire(projectile.owner, { kind = "HitConfirm", item = "Shield", attacker = victim.DisplayName })
		return
	end
	PassengerService.ApplyDamage(victim, cfg.Damage, "Tomato", projectile.owner)
	fire(victim, { kind = "Splat", item = "Tomato", coverage = cfg.SplatCoverage, seconds = cfg.WipeSeconds, attacker = projectile.owner.DisplayName })
	fire(projectile.owner, { kind = "HitConfirm", item = "Tomato", attacker = victim.DisplayName })
	broadcast({ kind = "Burst", item = "Tomato", position = at })
	onTomatoHit:Fire(projectile.owner, victim)
end

local function knockProp(part: BasePart, direction: Vector3, hitPosition: Vector3)
	local cfg = Config.Items.Prop
	if part.Anchored then
		return
	end
	local velocity = direction * cfg.KnockSpeed + Vector3.new(0, cfg.KnockSpeed * cfg.KnockLift, 0)
	part:ApplyImpulse(velocity * part.AssemblyMass)
	part:ApplyAngularImpulse(Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * part.AssemblyMass * 8)
	broadcast({ kind = "Burst", item = "Tomato", position = hitPosition })
end

local function triggerTrap(trap: Trap, victim: Player, victimEntry: VehicleService.VehicleEntry)
	local stats = Config.Vehicles.Stats[victimEntry.vehicleId]
	if stats and stats.ImmuneTo and stats.ImmuneTo[trap.kind] then
		fire(victim, { kind = "Immune", item = trap.kind })
		return
	end
	if consumeShield(victim, trap.position) then
		return
	end
	if trap.kind == "Banana" then
		local cfg = Config.Items.Banana
		victimEntry.spinUntil = now() + cfg.SpinSeconds
		victimEntry.lockedBy = trap.owner
		victimEntry.lockedUntil = now() + cfg.SpinSeconds
		fire(victim, { kind = "Spinout", item = "Banana", seconds = cfg.SpinSeconds })
		PassengerService.ApplyDamage(victim, cfg.Damage, "Banana", trap.owner)
		broadcast({ kind = "Burst", item = "Banana", position = trap.position })
	elseif trap.kind == "OilSlick" then
		local cfg = Config.Items.OilSlick
		victimEntry.lockedBy = trap.owner
		victimEntry.lockedUntil = now() + cfg.Seconds
		fire(victim, { kind = "Oil", item = "OilSlick", seconds = cfg.Seconds })
		PassengerService.ApplyDamage(victim, cfg.Damage, "OilSlick", trap.owner)
	end
end

local function stepProjectiles(dt: number)
	local t = now()
	local params = MapService.StaticRaycastParams()
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local cfg = Config.Items.Tomato
		local dead = t >= p.diesAt

		if not dead then
			-- Homing: lose the lock if the target is drifting or gone.
			if p.target then
				local targetEntry = VehicleService.GetEntry(p.target)
				if not targetEntry or targetEntry.drifting then
					p.target = nil
				else
					local desired = targetEntry.chassis.Position + Vector3.new(0, 1, 0) - p.position
					if desired.Magnitude > 0.01 then
						desired = desired.Unit
						local maxAngle = cfg.TurnRate * dt
						local cosAngle = math.clamp(p.direction:Dot(desired), -1, 1)
						local angle = math.acos(cosAngle)
						if angle <= maxAngle then
							p.direction = desired
						else
							local axis = p.direction:Cross(desired)
							if axis.Magnitude > 1e-4 then
								p.direction = CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(p.direction)
							end
						end
					end
				end
			end
			local step = p.direction * cfg.Speed * dt
			local hit = workspace:Raycast(p.position, step, params)
			if hit then
				dead = true
				if CollectionService:HasTag(hit.Instance, Config.Tags.Prop) then
					knockProp(hit.Instance, p.direction, hit.Position)
				else
					broadcast({ kind = "Burst", item = "Tomato", position = hit.Position })
				end
			else
				p.position += step
				p.part.CFrame = CFrame.lookAt(p.position, p.position + p.direction)
				for player, entry in VehicleService.GetAll() do
					if player ~= p.owner and (entry.chassis.Position - p.position).Magnitude <= cfg.HitRadius then
						hitWithTomato(p, player, entry)
						dead = true
						break
					end
				end
			end
		end

		if dead then
			p.part:Destroy()
			table.remove(projectiles, i)
		end
	end
end

local function stepTraps()
	local t = now()
	for i = #traps, 1, -1 do
		local trap = traps[i]
		local triggered = false
		if t >= trap.diesAt then
			triggered = true
		else
			for player, entry in VehicleService.GetAll() do
				if entry.chassis.Anchored then
					continue
				end
				if player == trap.owner and t < trap.armedForOwnerAt then
					continue
				end
				local pos = entry.chassis.Position
				if VecUtil.FlatDistance(pos, trap.position) <= trap.triggerRadius and math.abs(pos.Y - trap.position.Y) < 5 then
					triggerTrap(trap, player, entry)
					triggered = true
					break
				end
			end
		end
		if triggered then
			local parent = trap.part.Parent
			if parent and parent:IsA("Model") and parent.Parent == folder then
				parent:Destroy()
			else
				trap.part:Destroy()
			end
			table.remove(traps, i)
		end
	end
end

local function stepBoxes()
	local t = now()
	for _, box in boxes do
		if box.activeAt > 0 then
			if t >= box.activeAt then
				box.activeAt = 0
				setBoxActive(box, true)
			end
			continue
		end
		for player, entry in VehicleService.GetAll() do
			if not hasRoom(player) or entry.chassis.Anchored then
				continue
			end
			if (entry.chassis.Position - box.part.Position).Magnitude <= Config.Items.BoxRadius then
				addItem(player, roll(FareService.GetRankBucket(player)))
				box.activeAt = t + (boxRespawn or Config.Items.BoxRespawnSeconds)
				setBoxActive(box, false)
				break
			end
		end
	end
end

-- Fruit stands: a racer through one at speed smashes it, and gets a free item when its slot is empty.
local function stepStands()
	local cfg = Config.Chaos.FruitStands
	local t = now()
	for _, stand in stands do
		if stand.activeAt > 0 then
			if t >= stand.activeAt then
				stand.activeAt = 0
				setStandActive(stand, true)
			end
			continue
		end
		for player, entry in VehicleService.GetAll() do
			local velocity = entry.chassis.AssemblyLinearVelocity
			if entry.chassis.Anchored or velocity.Magnitude < cfg.MinSpeed then
				continue
			end
			if VecUtil.FlatDistance(entry.chassis.Position, stand.pivot.Position) <= cfg.Radius then
				stand.activeAt = t + cfg.RespawnSeconds
				setStandActive(stand, false, VecUtil.FlatUnit(velocity))
				local item: string? = if hasRoom(player) then roll(FareService.GetRankBucket(player)) else nil
				fire(player, { kind = "Smash", item = item })
				if item then
					addItem(player, item)
				end
				onSmash:Fire(player)
				break
			end
		end
	end
end

function ItemService.ClearAll()
	for _, p in projectiles do
		p.part:Destroy()
	end
	table.clear(projectiles)
	for _, trap in traps do
		local parent = trap.part.Parent
		if parent and parent:IsA("Model") and parent.Parent == folder then
			parent:Destroy()
		else
			trap.part:Destroy()
		end
	end
	table.clear(traps)
	table.clear(held)
	table.clear(spare)
	for _, player in Players:GetPlayers() do
		player:SetAttribute(Config.Vehicles.Phantom.ShieldAttribute, 0) -- built-in shields start each round charged
	end
	for player in shieldHits do
		VehicleService.SetHighlight(player, nil, 0)
	end
	table.clear(shieldHits)
	for _, box in boxes do
		box.activeAt = 0
		setBoxActive(box, true)
	end
	for _, stand in stands do
		stand.activeAt = 0
		setStandActive(stand, true)
	end
	MapService.ResetProps()
	for _, player in Players:GetPlayers() do
		fire(player, { kind = "Granted", item = "" })
	end
end

-- A bot went home: drop what it held (players are forgotten on PlayerRemoving).
function ItemService.Forget(player: Player)
	held[player] = nil
	spare[player] = nil
	shieldHits[player] = nil
end

-- Re-read item boxes and fruit stands from the current map (after MapService.LoadMap).
function ItemService.RefreshBoxes()
	boxes = {}
	for _, part in MapService.GetItemBoxes() do
		table.insert(boxes, { part = part, activeAt = 0 })
		setBoxActive(boxes[#boxes], true)
	end
	stands = {}
	for _, model in MapService.GetFruitStands() do
		local stand: Stand = { model = model, pivot = model:GetPivot(), activeAt = 0 }
		table.insert(stands, stand)
		setStandActive(stand, true)
	end
end

function ItemService.Init()
	folder = MapService.GetRuntimeFolder("Items")
	itemEvent = Remotes.Get("ItemEvent")
	ItemService.RefreshBoxes()

	Remotes.Get("UseItem").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "UseItem", Config.Net.RateLimits.UseItem) then
			return
		end
		ItemService.Use(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		held[player] = nil
		spare[player] = nil
		shieldHits[player] = nil
	end)
end

function ItemService.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		if not enabled then
			return
		end
		stepBoxes()
		stepStands()
		stepProjectiles(dt)
		stepTraps()
	end)
end

return ItemService
