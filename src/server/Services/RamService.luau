--!strict
-- Ramming (Config.Chaos.Ram): two racers' cars (players or bots) meeting with a closing speed above MinSpeed. The
-- faster car is the attacker; the other car's passenger takes damage scaled by the closing speed through
-- PassengerService.ApplyDamage (Seatbelt, Armored Seats, the Night Cab and the damage cooldown count; a raised Shield
-- takes it instead), its combo ends, and a bail it causes pays the attacker the Hunter Bonus. Both drivers see
-- RAMMED!; the hit car gets a shove along the attacker's line. The ram replaces the crash damage the bump's own speed
-- loss would otherwise do to either car.
-- Contact comes from the replicated positions (footprints grown by Padding), and the speeds from each car's fastest
-- moment in the last Lookback seconds, because by the time the server sees the cars touching they have already
-- slowed each other down.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Racers = require(script.Parent.Parent.Racers)
local VehicleService = require(script.Parent.VehicleService)
local PassengerService = require(script.Parent.PassengerService)
local ItemService = require(script.Parent.ItemService)
local ComboService = require(script.Parent.ComboService)

local RamService = {}

type Sample = { t: number, v: Vector3 }

local itemEvent: RemoteEvent
local history: { [Player]: { Sample } } = {} -- recent flat velocities per driver
local lastRam: { [string]: number } = {} -- pair key -> server time of their last ram

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function pairKey(a: Player, b: Player): string
	local x, y = a.UserId, b.UserId
	return if x < y then tostring(x) .. ":" .. tostring(y) else tostring(y) .. ":" .. tostring(x)
end

-- The fastest this car went in the last Lookback seconds (its speed going into the bump).
local function peakVelocity(player: Player): Vector3
	local best = Vector3.zero
	local samples: { Sample } = history[player] or {}
	for _, sample in samples do
		if sample.v.Magnitude > best.Magnitude then
			best = sample.v
		end
	end
	return best
end

-- One part's footprint on an axis: its centre and its reach (half extents grown by half the padding).
local function project(part: BasePart, axis: Vector3, pad: number): (number, number)
	local cf = part.CFrame
	local half = part.Size / 2
	local reach = math.abs(flat(cf.RightVector):Dot(axis)) * (half.X + pad / 2) + math.abs(flat(cf.LookVector):Dot(axis)) * (half.Z + pad / 2)
	local centre = flat(cf.Position):Dot(axis)
	return centre - reach, centre + reach
end

-- Do the two cars' padded footprints overlap (separating axes on the flat rectangles), at about the same height?
local function touching(a: BasePart, b: BasePart): boolean
	local cfg = Config.Chaos.Ram
	if math.abs(a.Position.Y - b.Position.Y) > cfg.MaxHeightGap then
		return false -- one is flying over the other
	end
	for _, part in { a, b } do
		for _, raw in { flat(part.CFrame.RightVector), flat(part.CFrame.LookVector) } do
			if raw.Magnitude > 0.01 then
				local axis = raw.Unit
				local a0, a1 = project(a, axis, cfg.Padding)
				local b0, b1 = project(b, axis, cfg.Padding)
				if a1 < b0 or b1 < a0 then
					return false
				end
			end
		end
	end
	return true
end

local function tell(player: Player, payload: { [string]: any })
	if not Racers.IsBot(player) then
		itemEvent:FireClient(player, payload)
	end
end

local function ram(attacker: Player, aEntry: VehicleService.VehicleEntry, victim: Player, vEntry: VehicleService.VehicleEntry, closing: number, now: number)
	local cfg = Config.Chaos.Ram
	-- the bump's own speed loss is the ram, not also a crash for either car
	for _, entry in { aEntry, vEntry } do
		entry.impact = nil
		entry.crashImmuneUntil = math.max(entry.crashImmuneUntil, now + cfg.CrashImmuneSeconds)
	end
	local share = math.clamp((closing - cfg.MinSpeed) / math.max(1, cfg.FullSpeed - cfg.MinSpeed), 0, 1)
	local damage = cfg.DamageMin + (cfg.DamageMax - cfg.DamageMin) * share
	local lost = 0
	local shielded = false
	if PassengerService.GetLoaded(victim) and not PassengerService.IsImmune(victim) then
		shielded = ItemService.AbsorbHit(victim, vEntry.chassis.Position)
		if not shielded then
			lost = PassengerService.ApplyDamage(victim, damage, "ram", attacker)
		end
	end
	ComboService.Reset(victim, "rammed")

	-- shove the hit car along the attacker's line (half at MinSpeed, full at FullSpeed)
	local line = flat(peakVelocity(attacker))
	if line.Magnitude < 0.1 then
		line = flat(vEntry.chassis.Position - aEntry.chassis.Position)
	end
	local push = (if line.Magnitude > 0.01 then line.Unit else Vector3.zero) * cfg.Shove * (0.5 + 0.5 * share)
	if Racers.IsBot(victim) then
		vEntry.chassis:ApplyImpulse(push * vEntry.chassis.AssemblyMass)
	end
	tell(victim, { kind = "Rammed", attacker = attacker.DisplayName, push = push })
	tell(attacker, { kind = "Ram", attacker = victim.DisplayName })
	if RunService:IsStudio() then
		print(string.format("[RamService] %s rammed %s at %d studs/s: -%d HP, shield %s", attacker.Name, victim.Name, math.floor(closing), math.round(lost), tostring(shielded)))
	end
end

local function step()
	local cfg = Config.Chaos.Ram
	local now = workspace:GetServerTimeNow()
	local live: { { player: Player, entry: VehicleService.VehicleEntry } } = {}
	for player, entry in VehicleService.GetAll() do
		local samples = history[player]
		if not samples then
			samples = {}
			history[player] = samples
		end
		table.insert(samples, { t = now, v = flat(entry.lastVelocity) })
		while #samples > 0 and now - samples[1].t > cfg.Lookback do
			table.remove(samples, 1)
		end
		if not entry.chassis.Anchored and entry.chassis.Parent then
			table.insert(live, { player = player, entry = entry })
		end
	end
	for player in history do
		if not VehicleService.GetEntry(player) then
			history[player] = nil
		end
	end

	for i = 1, #live do
		for j = i + 1, #live do
			local a, b = live[i], live[j]
			local ca, cb = a.entry.chassis, b.entry.chassis
			local gap = flat(cb.Position - ca.Position)
			local dist = gap.Magnitude
			if dist < 0.01 or dist > (ca.Size.Magnitude + cb.Size.Magnitude) / 2 + cfg.Padding then
				continue
			end
			local key = pairKey(a.player, b.player)
			if now - (lastRam[key] or -math.huge) < cfg.PairCooldown or not touching(ca, cb) then
				continue
			end
			local va, vb = peakVelocity(a.player), peakVelocity(b.player)
			local closing = (va - vb):Dot(gap / dist)
			if closing < cfg.MinSpeed then
				continue
			end
			lastRam[key] = now
			if va.Magnitude >= vb.Magnitude then
				ram(a.player, a.entry, b.player, b.entry, closing, now)
			else
				ram(b.player, b.entry, a.player, a.entry, closing, now)
			end
		end
	end
end

function RamService.Init()
	itemEvent = Remotes.Get("ItemEvent")
end

function RamService.Start()
	RunService.Heartbeat:Connect(step)
end

return RamService
