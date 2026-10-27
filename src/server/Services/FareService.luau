--!strict
-- The money side of passengers: pickup contests, destinations, timers, delivery, tips, stunt cash, quota, rank.
-- All money here is integer cents (Config is in dollars; Money.Cents converts). Three ledgers per player:
--   wallet       spendable at the Pit Stop, carried across the match
--   roundEarned  progress toward this round's quota; each round starts at Config.PitStop.CarryFrac of the wallet
--   matchEarned  everything earned this match (spending doesn't reduce it): the final standings

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Money = require(ReplicatedStorage.Shared.Money)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local VecUtil = require(ReplicatedStorage.Shared.VecUtil)
local MapService = require(script.Parent.MapService)
local VehicleService = require(script.Parent.VehicleService)
local PassengerService = require(script.Parent.PassengerService)
local ComboService = require(script.Parent.ComboService)
local Racers = require(script.Parent.Parent.Racers)

local FareService = {}

local onQuotaReached: Signal.Signal<Player> = Signal.new()
FareService.OnQuotaReached = onQuotaReached
local onDelivered: Signal.Signal<Player, string, number> = Signal.new()
local onClaimed: Signal.Signal<Player, string> = Signal.new()
local onGraded: Signal.Signal<Player, string> = Signal.new()
FareService.OnClaimed = onClaimed -- (player, tier) a passenger got in
FareService.OnGraded = onGraded -- (player, grade "Speedy" | "OnTime" | "Slow") a delivery's grade
FareService.OnDelivered = onDelivered -- (player, tier, tip shown)

local fares: { [Player]: Types.Fare } = {}
local wallet: { [Player]: number } = {}
local roundEarned: { [Player]: number } = {}
local matchEarned: { [Player]: number } = {}
local delivered: { [Player]: number } = {}
local bestTip: { [Player]: number } = {}
local enabled = false
local payMult = 1 -- Frenzy doubles delivery payouts
local forcedRequest: { [Player]: string } = {} -- Studio debug: the next passenger asks for this
local leader: Player? = nil -- this round's cash leader, wearing the bounty crown
local announced: Player? = nil -- the leader the last NEW LEADER banner named
local leaderBannerAt = -math.huge
local quota = Money.Cents(Config.Round.Quotas[1])
local rng = Random.new()
local fareEvent: RemoteEvent

local function fire(player: Player, payload: Types.FareEventPayload)
	if Racers.IsBot(player) then
		return -- bots have no client
	end
	fareEvent:FireClient(player, payload)
end

-- Spendable cash, in cents.
function FareService.GetCash(player: Player): number
	return wallet[player] or 0
end

-- This round's progress toward the quota, in cents.
function FareService.GetRoundEarned(player: Player): number
	return roundEarned[player] or 0
end

-- Money earned (cents): banks it, counts toward this round's quota and toward the match total.
function FareService.AddCash(player: Player, amount: number)
	wallet[player] = (wallet[player] or 0) + amount
	roundEarned[player] = (roundEarned[player] or 0) + amount
	matchEarned[player] = (matchEarned[player] or 0) + amount
	if enabled and (roundEarned[player] or 0) >= quota then
		onQuotaReached:Fire(player)
	end
end

-- Pit Stop spending: only the wallet goes down. False (and nothing spent) when it can't be afforded.
function FareService.Spend(player: Player, amount: number): boolean
	local have = wallet[player] or 0
	if have < amount then
		return false
	end
	wallet[player] = have - amount
	return true
end

-- Pit Stop undo: gives back exactly what Spend took (the wallet only, never quota progress).
function FareService.Refund(player: Player, amount: number)
	wallet[player] = (wallet[player] or 0) + amount
end

function FareService.GetFare(player: Player): Types.Fare?
	return fares[player]
end

-- This round's quota, in cents.
function FareService.GetQuota(): number
	return quota
end

-- `dollars` straight from Config.Round.Quotas.
function FareService.SetQuota(dollars: number)
	quota = Money.Cents(dollars)
end

-- Arcade: no quota to reach (the clock ends the run).
function FareService.DisableQuota()
	quota = math.huge
end

function FareService.SetEnabled(value: boolean)
	enabled = value
end

function FareService.TargetNpcCount(): number
	local players = #Racers.All()
	local want = players * Config.Fares.NpcsPerPlayer
	local maxCount = math.min(Config.Fares.MaxNpcs, #MapService.GetPickups())
	return math.clamp(want, math.min(Config.Fares.MinNpcs, maxCount), maxCount)
end

-- Frenzy: every delivery pays this many times over (1 the rest of the time).
function FareService.SetPayMult(mult: number)
	payMult = mult
end

-- The bounty: this round's cash leader, or nil before anyone has MinCash (and in a race of one).
function FareService.GetLeader(): Player?
	return leader
end

-- The crown changes hands only when someone passes the leader outright. Everyone hears about it: at most one banner
-- per BannerCooldown, and a swap inside the cooldown is announced when it ends (if they still lead).
local function updateLeader()
	local cfg = Config.Chaos.Bounty
	local racers = Racers.All()
	local minCash = Money.Cents(cfg.MinCash)
	local best: Player? = nil
	local bestCash = 0
	for _, racer in racers do
		local cash = roundEarned[racer] or 0
		if cash > bestCash then
			best, bestCash = racer, cash
		end
	end
	local current = leader
	local currentCash = if current and current.Parent then roundEarned[current] or 0 else -1
	local nextLeader = current
	if #racers < 2 then
		nextLeader = nil
	elseif not current or currentCash < minCash then
		nextLeader = if bestCash >= minCash then best else nil
	elseif best and best ~= current and bestCash > currentCash then
		nextLeader = best
	end
	leader = nextLeader
	local now = workspace:GetServerTimeNow()
	if not nextLeader or nextLeader == announced or now - leaderBannerAt < cfg.BannerCooldown then
		return
	end
	announced = nextLeader
	leaderBannerAt = now
	local name = (if Racers.IsBot(nextLeader) then "BOT " else "") .. nextLeader.DisplayName
	for _, player in Players:GetPlayers() do
		fire(player, { kind = "NewLeader", line = name, you = if player == nextLeader then true else nil })
	end
end

-- Drivers (players and bots) sorted by this round's earnings (or the match total), then deliveries, then UserId.
local function sortedPlayers(byMatch: boolean?): { Player }
	local score = if byMatch then matchEarned else roundEarned
	local list = Racers.All()
	table.sort(list, function(a, b)
		local ca, cb = score[a] or 0, score[b] or 0
		if ca ~= cb then
			return ca > cb
		end
		local da, db = delivered[a] or 0, delivered[b] or 0
		if da ~= db then
			return da > db
		end
		return a.UserId < b.UserId
	end)
	return list
end

function FareService.GetRanks(): { [Player]: number }
	local ranks: { [Player]: number } = {}
	for i, player in sortedPlayers() do
		ranks[player] = i
	end
	return ranks
end

function FareService.GetRankBucket(player: Player): Types.RankBucket
	local list = sortedPlayers()
	if #list <= 1 then
		return "Mid"
	end
	local rank = table.find(list, player)
	if rank == 1 then
		return "Leader"
	elseif rank == #list then
		return "Last"
	end
	return "Mid"
end

-- Round podium (`byMatch` false: this round's earnings) or final standings (`byMatch` true: the match total).
function FareService.GetResults(byMatch: boolean?): { Types.PodiumEntry }
	local score = if byMatch then matchEarned else roundEarned
	local results: { Types.PodiumEntry } = {}
	for _, player in sortedPlayers(byMatch) do
		table.insert(results, {
			id = player.UserId,
			name = player.DisplayName,
			cash = score[player] or 0,
			fares = delivered[player] or 0,
			bestTip = bestTip[player] or 0,
			bot = if Racers.IsBot(player) then true else nil,
		})
	end
	return results
end

-- New match: everything to zero.
function FareService.ResetMatch()
	leader = nil
	announced = nil
	table.clear(fares)
	for _, player in Racers.All() do
		wallet[player] = 0
		roundEarned[player] = 0
		matchEarned[player] = 0
		delivered[player] = 0
		bestTip[player] = 0
	end
end

-- New round inside a match: active fares drop; the quota count restarts at a head start of the unspent wallet.
function FareService.ResetRound()
	leader = nil
	announced = nil
	table.clear(fares)
	for _, player in Racers.All() do
		roundEarned[player] = math.floor((wallet[player] or 0) * Config.PitStop.CarryFrac)
	end
end

-- A bot went home: forget its money and fare (players are forgotten on PlayerRemoving).
function FareService.RemoveRacer(player: Player)
	fares[player] = nil
	wallet[player] = nil
	roundEarned[player] = nil
	matchEarned[player] = nil
	delivered[player] = nil
	bestTip[player] = nil
end

local function pickDestination(npc: PassengerService.Npc): MapService.Point?
	local tierDef = Config.Fares.Tiers[npc.tier]
	local candidates: { MapService.Point } = {}
	local closestToBand: MapService.Point? = nil
	local closestGap = math.huge
	local mid = (tierDef.MinTrip + math.min(tierDef.MaxTrip, tierDef.MinTrip + 200)) / 2
	for _, point in MapService.GetDropoffs() do
		local d = VecUtil.FlatDistance(point.position, npc.position)
		if d >= tierDef.MinTrip and d < tierDef.MaxTrip then
			table.insert(candidates, point)
		end
		local gap = math.abs(d - mid)
		if gap < closestGap then
			closestGap = gap
			closestToBand = point
		end
	end
	if #candidates > 0 then
		return candidates[rng:NextInteger(1, #candidates)]
	end
	return closestToBand
end

-- A passenger request for this pickup (people only), or nil.
local function rollRequest(player: Player): { Id: string, Stunt: string, Goal: number, Single: boolean, Unit: string, Label: string, Shout: string }?
	local cfg = Config.Chaos.Requests
	if Racers.IsBot(player) then
		return nil
	end
	local forced = forcedRequest[player]
	forcedRequest[player] = nil
	if not forced and rng:NextNumber() >= cfg.Chance then
		return nil
	end
	for _, def in cfg.List do
		if def.Id == forced then
			return def
		end
	end
	return cfg.List[rng:NextInteger(1, #cfg.List)]
end

local function claim(player: Player, npc: PassengerService.Npc)
	local destination: MapService.Point? = nil
	if npc.destinationIndex then
		destination = MapService.GetDropoff(npc.destinationIndex)
	end
	if not destination then
		destination = pickDestination(npc)
	end
	if not destination then
		return
	end
	npc.destinationIndex = destination.index
	local distance = VecUtil.FlatDistance(destination.position, npc.position)
	local now = workspace:GetServerTimeNow()
	local duration = Config.Fares.TimeBase + distance / Config.Fares.TimeSpeed
	local tierDef = Config.Fares.Tiers[npc.tier]
	local fare: Types.Fare = {
		npcId = npc.id,
		expired = false,
		tier = npc.tier,
		base = Money.Cents(tierDef.Base) * (if npc.golden then Config.Golden.PayMult else 1),
		kind = npc.kind,
		golden = npc.golden,
		pickupIndex = npc.pickupIndex,
		destinationIndex = destination.index,
		destination = destination.position,
		startedAt = now,
		deadline = now + duration,
		distance = distance,
		stuntTips = 0,
		request = nil,
		requestProgress = 0,
		requestDone = false,
	}
	local request = rollRequest(player)
	if request then
		fare.request = request.Id
	end
	local npcPosition = npc.position
	PassengerService.Board(npc, player)
	fares[player] = fare
	onClaimed:Fire(player, npc.tier)
	fire(player, {
		kind = "Claimed",
		npcId = npc.id,
		tier = npc.tier,
		base = fare.base,
		destination = destination.position,
		destinationIndex = destination.index,
		destinationName = destination.name,
		startedAt = now,
		deadline = fare.deadline,
		passenger = npc.kind,
		golden = npc.golden,
		request = fare.request,
	})
	-- Everyone else nearby and empty sees TAKEN.
	for other, entry in VehicleService.GetAll() do
		if other ~= player and not fares[other] and VecUtil.FlatDistance(entry.chassis.Position, npcPosition) <= Config.Fares.TakenNoticeRadius then
			fire(other, { kind = "Taken", npcId = npc.id, position = npcPosition })
		end
	end
end

-- The Tip Jar Pit Stop card multiplies tips, stunt cash included.
local function tipJarMult(player: Player): number
	local tipJar = player:GetAttribute("Pit_TipJar")
	return if typeof(tipJar) == "number" then tipJar else 1
end

-- An accepted stunt: cash into the current fare at once, more per chain step, capped per fare. The popup fires either
-- way, so a stunt with no passenger still shows its name.
local function onStunt(player: Player, kind: string, units: number, chain: number)
	local cfg = Config.Stunts
	local fare = fares[player]
	local amount = 0
	if enabled and fare and not fare.expired then
		local kindDef = Config.PassengerTypes.Kinds[fare.kind]
		local stuntMult = if kindDef then kindDef.StuntMult else 1 -- Thrill Seekers pay double, and their cap doubles too
		local raw = Money.Cents(units * (cfg.Pay[kind] or 0)) * (1 + cfg.ChainBonus * (chain - 1)) * tipJarMult(player) * stuntMult
		local room = math.max(0, math.round(fare.base * cfg.MaxPerFareFrac * stuntMult) - fare.stuntTips)
		amount = math.min(room, math.round(raw))
		if amount > 0 then
			fare.stuntTips += amount
			if not cfg.HoldUntilDelivery then
				FareService.AddCash(player, amount)
			end
		end
	end
	fire(player, { kind = "Stunt", stunt = kind, amount = amount, chain = chain, stunts = if fare then fare.stuntTips else nil })

	-- The passenger's request: this stunt counts toward it (one big enough stunt, or a running total).
	local id = if enabled and fare and not fare.expired and not fare.requestDone then fare.request else nil
	if fare and id then
		for _, def in Config.Chaos.Requests.List do
			if def.Id == id and def.Stunt == kind then
				local value = if kind == "NearMiss" then 1 else units * cfg.UnitSeconds
				fare.requestProgress = if def.Single then math.max(fare.requestProgress, value) else fare.requestProgress + value
				if fare.requestProgress >= def.Goal then
					fare.requestDone = true
				end
				local bonus = math.round(fare.base * Config.Chaos.Requests.BonusFrac)
				fire(player, { kind = "Request", request = id, progress = fare.requestProgress, done = fare.requestDone, payout = if fare.requestDone then bonus else nil })
			end
		end
	end
end

-- Studio: the next passenger this driver picks up asks for this request.
function FareService.DebugForceRequest(player: Player, id: string)
	if RunService:IsStudio() then
		forcedRequest[player] = id
	end
end

local function finishDelivery(player: Player, fare: Types.Fare, npc: PassengerService.Npc, now: number, allowTip: boolean)
	local total = math.max(0.01, fare.deadline - fare.startedAt)
	local timeFrac = VecUtil.Clamp01((fare.deadline - now) / total)
	local hpFrac = VecUtil.Clamp01(npc.hp / npc.maxHp)
	local tips = Config.Tips
	local speedy = VecUtil.Clamp01((timeFrac - tips.TimeFloor) / (tips.TimeCeil - tips.TimeFloor))
	local chill = VecUtil.Clamp01((hpFrac - tips.HpFloor) / (1 - tips.HpFloor))
	local tipRaw = if allowTip then fare.base * tips.MaxFrac * (tips.TimeWeight * speedy + tips.ChillWeight * chill) else 0
	tipRaw *= tipJarMult(player)
	if Racers.IsBot(player) then
		tipRaw *= Config.Bots.TipMult
	end
	-- The passenger's kind bends the tip: a Thrill Seeker who got no stunt halves it, a Nervous one who arrived without
	-- a scratch doubles it. `bonus` tells the driver why.
	local bonus: string? = if fare.golden then Config.Golden.PayLine else nil
	local kindDef = Config.PassengerTypes.Kinds[fare.kind]
	if kindDef and allowTip then
		local mult = 1
		if fare.stuntTips <= 0 then
			mult *= kindDef.NoStuntTipMult
		end
		if npc.hp >= npc.maxHp then
			mult *= kindDef.SmoothTipMult
		end
		if mult ~= 1 then
			tipRaw *= mult
			bonus = if bonus then bonus .. "  ·  " .. kindDef.TipLine else kindDef.TipLine
		end
	end
	local tipShown = math.round(tipRaw)
	-- a request done on the way: BonusFrac of the base on top of the tip
	if allowTip and fare.requestDone then
		tipShown += math.round(fare.base * Config.Chaos.Requests.BonusFrac)
		local line = Config.Chaos.Requests.PayLine
		bonus = if bonus then bonus .. "  ·  " .. line else line
	end
	-- Stunt cash rides in the fare (Config.Stunts.HoldUntilDelivery) and is lost with the tip on a late arrival.
	local stunts = if allowTip then fare.stuntTips else 0
	local held = if Config.Stunts.HoldUntilDelivery then stunts else 0
	local payout = fare.base + tipShown + held
	if payMult ~= 1 then
		payout = math.round(payout * payMult)
		local line = Config.Chaos.Frenzy.PayLine
		bonus = if bonus then bonus .. "  ·  " .. line else line
	end
	local grades = Config.Grades
	local grade = if not allowTip then "Slow" elseif timeFrac >= grades.SpeedyFrac then "Speedy" elseif timeFrac >= grades.OnTimeFrac then "OnTime" else "Slow"

	fares[player] = nil
	delivered[player] = (delivered[player] or 0) + 1
	bestTip[player] = math.max(bestTip[player] or 0, tipShown + stunts)
	PassengerService.Deliver(player)
	fire(player, {
		kind = "Delivered",
		tier = fare.tier,
		base = fare.base,
		payout = payout,
		tip = tipShown,
		stunts = stunts,
		grade = grade,
		line = if allowTip then nil else "LATE. NO TIP.",
		bonus = bonus,
	})
	FareService.AddCash(player, payout)
	onDelivered:Fire(player, fare.tier, tipShown + stunts)
	onGraded:Fire(player, grade)

	task.delay(Config.Fares.RespawnDelay, function()
		if enabled then
			PassengerService.EnsureCount(FareService.TargetNpcCount())
		end
	end)
end

local function handleBail(victim: Player, npc: PassengerService.Npc, reason: string, attacker: Player?)
	local fare = fares[victim]
	fares[victim] = nil
	ComboService.Reset(victim, "bail")
	fire(victim, {
		kind = "Bailed",
		reason = reason,
		tier = npc.tier,
		base = if fare then fare.base else 0,
	})
	-- Hunter Bonus: the rival who made them bail gets a share of the lost fare; double when it was the leader's.
	if RunService:IsStudio() then
		print(string.format("[FareService] %s's passenger bailed (%s), credit %s, fare %s", victim.Name, reason, if attacker then attacker.Name else "nobody", tostring(fare ~= nil)))
	end
	if attacker and fare and attacker ~= victim and attacker.Parent then
		local bounty = victim == leader
		local bonus = math.round(fare.base * Config.Items.HunterBonusFrac * (if bounty then Config.Chaos.Bounty.Mult else 1))
		if bonus > 0 then
			fire(attacker, { kind = "HunterBonus", payout = bonus, line = victim.DisplayName, bounty = if bounty then true else nil })
			FareService.AddCash(attacker, bonus)
		end
	end
end

local function tick()
	if not enabled then
		return
	end
	updateLeader()
	local now = workspace:GetServerTimeNow()
	local vehicles = VehicleService.GetAll()

	-- Pickup contest: every stopped, empty taxi near an available NPC bids; the closest bid per NPC wins this tick.
	local bids: { [number]: { player: Player, npc: PassengerService.Npc, dist: number } } = {}
	local losers: { Player } = {}
	for player, entry in vehicles do
		if fares[player] or entry.chassis.Anchored then
			continue
		end
		if entry.chassis.AssemblyLinearVelocity.Magnitude > Config.Fares.StopSpeed then
			continue
		end
		local npc, dist = PassengerService.GetAvailableNear(entry.chassis.Position, Config.Fares.PickupRadius)
		if npc then
			local current = bids[npc.id]
			if not current then
				bids[npc.id] = { player = player, npc = npc, dist = dist }
			elseif dist < current.dist then
				table.insert(losers, current.player)
				bids[npc.id] = { player = player, npc = npc, dist = dist }
			else
				table.insert(losers, player)
			end
		end
	end
	for _, bid in bids do
		claim(bid.player, bid.npc)
	end
	for _, loser in losers do
		fire(loser, { kind = "Taken" })
	end

	-- Deliveries and timeouts.
	for player, fare in fares do
		local entry = vehicles[player]
		local npc = PassengerService.GetLoaded(player)
		if not entry or not npc then
			fares[player] = nil
			continue
		end
		local pos = entry.chassis.Position
		local speed = entry.chassis.AssemblyLinearVelocity.Magnitude
		if VecUtil.FlatDistance(pos, fare.destination) <= Config.Fares.DeliverRadius and speed <= Config.Fares.StopSpeed then
			finishDelivery(player, fare, npc, now, not fare.expired)
		elseif now >= fare.deadline and not fare.expired then
			if Config.Fares.TimeoutBails then
				PassengerService.Bail(player, "timeout")
			else
				-- Tip is gone; the passenger still has to be delivered for the base fare.
				fare.expired = true
				fire(player, { kind = "Expired", tier = fare.tier, base = fare.base })
			end
		end
	end
end

-- Studio: this driver claims the nearest waiting passenger, wherever they are (to test what happens with one aboard).
function FareService.DebugClaimNearest(player: Player)
	local entry = VehicleService.GetEntry(player)
	if not RunService:IsStudio() or not entry or fares[player] then
		return
	end
	local npc = PassengerService.GetAvailableNear(entry.chassis.Position, math.huge)
	if npc then
		claim(player, npc)
	end
end

function FareService.Init()
	fareEvent = Remotes.Get("FareEvent")
	PassengerService.OnBailed:Connect(handleBail)
	ComboService.OnStunt:Connect(onStunt)
	ComboService.OnChainBroken:Connect(function(player: Player, chain: number, reason: string)
		fire(player, { kind = "ChainBroken", chain = chain, reason = reason })
	end)
	PassengerService.OnDamaged:Connect(function(player: Player, amount: number, source: string)
		-- What the passenger yells about it comes from the rider in the cab (RiderService), where everyone sees it.
		fire(player, { kind = "Hurt", amount = math.round(amount), source = source })
	end)
	PassengerService.OnGoldenSpawned:Connect(function(npc: PassengerService.Npc)
		for _, player in Players:GetPlayers() do
			fire(player, { kind = "Golden", npcId = npc.id, position = npc.position, tier = npc.tier })
		end
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		wallet[player] = 0
		roundEarned[player] = 0
		matchEarned[player] = 0
		delivered[player] = 0
		bestTip[player] = 0
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		fares[player] = nil
		wallet[player] = nil
		roundEarned[player] = nil
		matchEarned[player] = nil
		delivered[player] = nil
		bestTip[player] = nil
	end)
end

function FareService.Start()
	RunService.Heartbeat:Connect(tick)
end

return FareService
