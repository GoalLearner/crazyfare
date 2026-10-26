--!strict
-- Item boxes, the one-slot inventory, rank-weighted rolls, and every item's server-side effect:
-- Tomato (homing projectile), Banana (trap), LemonNitro (boost). Clients only render what they are told.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Types = require(ReplicatedStorage.Shared.Types)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local PassengerService = require(script.Parent.PassengerService)
local FareService = require(script.Parent.FareService)

type Box = { part: BasePart, activeAt: number }
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
	armedForOwnerAt: number,
	diesAt: number,
}

local ItemService = {}

local held: { [Player]: string } = {}
local boxes: { Box } = {}
local projectiles: { Projectile } = {}
local traps: { Trap } = {}
local enabled = false
local rng = Random.new()
local folder: Folder
local itemEvent: RemoteEvent

local function fire(player: Player, payload: Types.ItemEventPayload)
	itemEvent:FireClient(player, payload)
end

local function broadcast(payload: Types.ItemEventPayload)
	itemEvent:FireAllClients(payload)
end

local function now(): number
	return workspace:GetServerTimeNow()
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

function ItemService.Give(player: Player, item: string)
	if not Config.Items.Pool[item] then
		return
	end
	held[player] = item
	fire(player, { kind = "Granted", item = item })
end

function ItemService.SetEnabled(value: boolean)
	enabled = value
end

local function setBoxActive(box: Box, active: boolean)
	box.part:SetAttribute("Active", active)
end

-- Nearest loaded rival inside LockRange, or nil.
local function pickTarget(owner: Player, from: Vector3): Player?
	local best: Player? = nil
	local bestDist = Config.Items.Tomato.LockRange
	for player, entry in VehicleService.GetAll() do
		if player ~= owner and PassengerService.GetLoaded(player) then
			local d = (entry.chassis.Position - from).Magnitude
			if d < bestDist then
				bestDist = d
				best = player
			end
		end
	end
	return best
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

	local part = Instance.new("Part")
	part.Name = "Tomato"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.8, 1.8, 1.8)
	part.Color = Config.Items.Pool.Tomato.Color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.lookAt(origin, origin + direction)
	part:SetAttribute("OwnerUserId", owner.UserId)
	CollectionService:AddTag(part, Config.Tags.Projectile)
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

local function dropBanana(owner: Player, entry: VehicleService.VehicleEntry)
	local cfg = Config.Items.Banana
	local behind = (entry.chassis.CFrame * CFrame.new(0, 0, 5.5 + cfg.DropBack)).Position
	local groundY = MapService.GroundY(behind, entry.chassis.Position.Y - 2)
	local position = Vector3.new(behind.X, groundY + 0.5, behind.Z)

	local part = Instance.new("Part")
	part.Name = "Banana"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(2.6, 1, 1)
	part.Color = Config.Items.Pool.Banana.Color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	part:SetAttribute("OwnerUserId", owner.UserId)
	part:SetAttribute("TrapKind", "Banana")
	CollectionService:AddTag(part, Config.Tags.Trap)
	part.Parent = folder

	table.insert(traps, {
		part = part,
		owner = owner,
		kind = "Banana",
		position = position,
		armedForOwnerAt = now() + cfg.OwnerImmunity,
		diesAt = now() + cfg.Lifetime,
	})
end

local function applyBoost(player: Player, entry: VehicleService.VehicleEntry)
	local cfg = Config.Items.LemonNitro
	entry.boostUntil = now() + cfg.Seconds
	fire(player, { kind = "Boost", item = "LemonNitro", seconds = cfg.Seconds })
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

	if Config.Items.SelfCostItems[item] then
		PassengerService.ApplySelfCost(player)
	end

	if item == "Tomato" then
		launchTomato(player, entry)
	elseif item == "Banana" then
		dropBanana(player, entry)
	elseif item == "LemonNitro" then
		applyBoost(player, entry)
	end
end

local function hitWithTomato(projectile: Projectile, victim: Player, victimEntry: VehicleService.VehicleEntry)
	local cfg = Config.Items.Tomato
	PassengerService.ApplyDamage(victim, cfg.Damage, "Tomato")
	fire(victim, { kind = "Splat", item = "Tomato", coverage = cfg.SplatCoverage, seconds = cfg.WipeSeconds, attacker = projectile.owner.DisplayName })
	fire(projectile.owner, { kind = "HitConfirm", item = "Tomato", attacker = victim.DisplayName })
	broadcast({ kind = "Burst", item = "Tomato", position = victimEntry.chassis.Position })
end

local function triggerTrap(trap: Trap, victim: Player, victimEntry: VehicleService.VehicleEntry)
	if trap.kind == "Banana" then
		local cfg = Config.Items.Banana
		victimEntry.spinUntil = now() + cfg.SpinSeconds
		fire(victim, { kind = "Spinout", item = "Banana", seconds = cfg.SpinSeconds })
		PassengerService.ApplyDamage(victim, cfg.Damage, "Banana")
		broadcast({ kind = "Burst", item = "Banana", position = trap.position })
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
				broadcast({ kind = "Burst", item = "Tomato", position = hit.Position })
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
			local cfg = Config.Items.Banana
			for player, entry in VehicleService.GetAll() do
				if entry.chassis.Anchored then
					continue
				end
				if player == trap.owner and t < trap.armedForOwnerAt then
					continue
				end
				local pos = entry.chassis.Position
				if VecUtil.FlatDistance(pos, trap.position) <= cfg.TriggerRadius and math.abs(pos.Y - trap.position.Y) < 5 then
					triggerTrap(trap, player, entry)
					triggered = true
					break
				end
			end
		end
		if triggered then
			trap.part:Destroy()
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
			if held[player] or entry.chassis.Anchored then
				continue
			end
			if (entry.chassis.Position - box.part.Position).Magnitude <= Config.Items.BoxRadius then
				local item = roll(FareService.GetRankBucket(player))
				held[player] = item
				fire(player, { kind = "Granted", item = item })
				box.activeAt = t + Config.Items.BoxRespawnSeconds
				setBoxActive(box, false)
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
		trap.part:Destroy()
	end
	table.clear(traps)
	table.clear(held)
	for _, box in boxes do
		box.activeAt = 0
		setBoxActive(box, true)
	end
	for _, player in Players:GetPlayers() do
		fire(player, { kind = "Granted", item = "" })
	end
end

function ItemService.Init()
	folder = MapService.GetRuntimeFolder("Items")
	itemEvent = Remotes.Get("ItemEvent")
	boxes = {}
	for _, part in MapService.GetItemBoxes() do
		table.insert(boxes, { part = part, activeAt = 0 })
		setBoxActive(boxes[#boxes], true)
	end

	Remotes.Get("UseItem").OnServerEvent:Connect(function(player: Player)
		if not RateLimiter.Allow(player, "UseItem", Config.Net.RateLimits.UseItem) then
			return
		end
		ItemService.Use(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		held[player] = nil
	end)
end

function ItemService.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		if not enabled then
			return
		end
		stepBoxes()
		stepProjectiles(dt)
		stepTraps()
	end)
end

return ItemService
