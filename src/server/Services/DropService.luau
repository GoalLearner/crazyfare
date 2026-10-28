--!strict
-- Post-match drops (Config.Drops, owner spec 2026-10-28): every person who finishes a match opens one free crate.
-- Placement picks the tier (1st Gold, 2nd-3rd Silver, the rest Bronze), the tier's odds pick the rarity, weights pick
-- the prize. Pity: the PityEpic-th drop since the last Epic or better rolls among Epic and up. A car or paint you
-- already own pays DuplicateGems instead; boost tokens stack (you start a later match holding the item). Drop Gems go
-- straight to the profile: no VIP, event or any other purchase multiplies them, and nothing can buy or reroll a drop.
-- Bots get none. A Mythic pull is told to everyone in the server.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local PassengerService = require(script.Parent.PassengerService)
local SessionService = require(script.Parent.SessionService)

local DropService = {}

local cfg = Config.Drops
local rng = Random.new()
local dropEvent: RemoteEvent

local function rarityIndex(rarity: string): number
	return table.find(cfg.Rarities, rarity) or 1
end

local EPIC = rarityIndex("Epic")

local function tierFor(place: number): string
	return cfg.TierByPlace[place] or cfg.DefaultTier
end

-- A rarity from the tier's odds, among rarities at or above `minIndex` (pity raises it to Epic).
local function rollRarity(tier: string, minIndex: number): string
	local odds = cfg.TierOdds[tier] or cfg.TierOdds[cfg.DefaultTier]
	local total = 0
	for i, rarity in cfg.Rarities do
		if i >= minIndex then
			total += odds[rarity] or 0
		end
	end
	local pick = rng:NextNumber() * total
	for i, rarity in cfg.Rarities do
		if i >= minIndex then
			pick -= odds[rarity] or 0
			if pick <= 0 then
				return rarity
			end
		end
	end
	return cfg.Rarities[#cfg.Rarities]
end

local function rollPrize(rarity: string): Config.DropEntry
	local total = 0
	for _, entry in cfg.Pool do
		if entry.Rarity == rarity then
			total += entry.Weight
		end
	end
	local pick = rng:NextNumber() * total
	local last: Config.DropEntry = cfg.Pool[1]
	for _, entry in cfg.Pool do
		if entry.Rarity == rarity then
			last = entry
			pick -= entry.Weight
			if pick <= 0 then
				return entry
			end
		end
	end
	return last
end

-- One roll from a crate of this tier (pity: minIndex raises the floor). Pure: Studio checks the odds with it.
function DropService.Roll(tier: string, minIndex: number): Config.DropEntry
	return rollPrize(rollRarity(tier, minIndex))
end

local function findPrize(id: string): Config.DropEntry?
	for _, entry in cfg.Pool do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

-- What the reveal calls it.
local function prizeName(entry: Config.DropEntry): string
	local names = cfg.Names
	if entry.Kind == "Gems" then
		return string.format(names.Gems, tostring(entry.Amount or 0))
	elseif entry.Kind == "Paint" then
		return string.format(names.Paint, string.upper(entry.Ref or ""))
	elseif entry.Kind == "Vehicle" then
		local stats = Config.Vehicles.Stats[entry.Ref or ""]
		return string.format(names.Vehicle, string.upper(if stats then stats.DisplayName else entry.Ref or ""))
	elseif entry.Kind == "Boost" then
		local item = Config.Items.Pool[entry.Ref or ""]
		return string.format(names.Boost, string.upper(if item then item.DisplayName else entry.Ref or ""))
	elseif entry.Kind == "Trail" then
		local def = Config.Cosmetics.Trails[entry.Ref or ""]
		return string.format(names.Trail, if def then def.Name else entry.Ref or "")
	elseif entry.Kind == "Horn" then
		local def = Config.Cosmetics.Horns[entry.Ref or ""]
		return string.format(names.Horn, if def then def.Name else entry.Ref or "")
	elseif entry.Kind == "Card" then
		local def = Config.Cosmetics.Cards[entry.Ref or ""]
		return string.format(names.Card, if def then def.Name else entry.Ref or "")
	end
	return entry.Id
end

-- Hands the prize over. Returns the Gems paid instead when it was already yours (0 when new).
local function grant(player: Player, d: DataService.ProfileData, entry: Config.DropEntry): number
	local ref = entry.Ref or ""
	local duplicate = false
	if entry.Kind == "Gems" then
		local amount = entry.Amount or 0
		DataService.AddGems(player, amount)
		d.TotalGemsEarned += amount
	elseif entry.Kind == "Paint" then
		if (d.Inventory.Paints[ref] or 0) > 0 then
			duplicate = true
		else
			d.Inventory.Paints[ref] = 1
		end
	elseif entry.Kind == "Vehicle" then
		if d.OwnedVehicles[ref] == true or (Config.Vehicles.Stats[ref] ~= nil and DataService.Owns(player, ref)) then
			duplicate = true
		else
			d.OwnedVehicles[ref] = true
			local stats = Config.Vehicles.Stats[ref]
			if stats and stats.Mythic then
				LeaderboardService.RegisterPhantom(player) -- the next serial on the owners board
			end
		end
	elseif entry.Kind == "Boost" then
		d.Inventory.Boosts[ref] = (d.Inventory.Boosts[ref] or 0) + 1
	elseif entry.Kind == "Trail" or entry.Kind == "Horn" or entry.Kind == "Card" then
		local owned = d.Inventory[entry.Kind .. "s"]
		if (owned[ref] or 0) > 0 then
			duplicate = true
		else
			owned[ref] = 1
			if entry.Kind == "Card" then
				d.WeirdoQueue = ref -- the new card's weirdo rides in your next round
			end
		end
	end
	if not duplicate then
		return 0
	end
	local gems = cfg.DuplicateGems[entry.Rarity] or 0
	DataService.AddGems(player, gems)
	d.TotalGemsEarned += gems
	return gems
end

-- One crate for one person: roll (or the forced rarity / prize), grant, count pity, tell them, tell everyone on a
-- Mythic. `quiet` skips the reveal (the Studio burst).
local function open(player: Player, place: number, forceRarity: string?, forcePrize: string?, quiet: boolean?): Types.DropEventPayload?
	local d = DataService.Get(player)
	if not d then
		return nil
	end
	local tier = tierFor(place)
	local entry: Config.DropEntry
	local forced = if forcePrize then findPrize(forcePrize) else nil
	if forced then
		entry = forced
	else
		local minIndex = if d.PityCounter + 1 >= cfg.PityEpic then EPIC else 1
		entry = if forceRarity then rollPrize(forceRarity) else DropService.Roll(tier, minIndex)
	end
	local duplicateGems = grant(player, d, entry)
	d.DropCount += 1
	if rarityIndex(entry.Rarity) >= EPIC then
		d.PityCounter = 0
	else
		d.PityCounter += 1
	end
	DataService.Sync(player)
	local payload: Types.DropEventPayload = {
		kind = "Drop",
		tier = tier,
		rarity = entry.Rarity,
		prize = entry.Id,
		name = prizeName(entry),
		duplicateGems = if duplicateGems > 0 then duplicateGems else nil,
		pity = d.PityCounter,
	}
	if RunService:IsStudio() then
		print(string.format("[DropService] %s opened a %s crate: %s %s%s", player.Name, tier, entry.Rarity, entry.Id, if duplicateGems > 0 then string.format(" (duplicate, +%d gems)", duplicateGems) else ""))
	end
	if quiet then
		return payload
	end
	dropEvent:FireClient(player, payload)
	if entry.Rarity == "Mythic" then
		dropEvent:FireAllClients({
			kind = "Mythic",
			rarity = entry.Rarity,
			prize = entry.Id,
			name = payload.name,
			who = player.DisplayName,
			phantom = entry.Ref == cfg.PhantomRef,
		})
	end
	return payload
end

-- MatchController.MatchEnd: everyone on the podium who is a person opens a crate by their place.
function DropService.AwardMatch(results: { Types.PodiumEntry })
	for place, entry in results do
		local player = Players:GetPlayerByUserId(entry.id) -- nil for a bot
		if player and DataService.IsLoaded(player) then
			open(player, place)
		end
	end
end

-- RoundService, a few seconds into a round: every driver with a new card's weirdo queued gets it as a bonus fare at a
-- free curb (theirs alone for Config.Cosmetics.Bonus.HeadStartSeconds). No free curb: it waits for the next round.
function DropService.SpawnWeirdos()
	for _, player in SessionService.GetDrivers() do
		local d = DataService.Get(player)
		local card = if d then Config.Cosmetics.Cards[d.WeirdoQueue] else nil
		if not d or not card then
			continue
		end
		local npc = PassengerService.SpawnWeirdo(player, d.WeirdoQueue)
		if npc then
			dropEvent:FireClient(player, { kind = "Weirdo", card = d.WeirdoQueue, text = string.format(Config.Cosmetics.Bonus.Notice, card.Name) })
			if RunService:IsStudio() then
				print(string.format("[DropService] %s's %s is waiting at curb %d", player.Name, d.WeirdoQueue, npc.pickupIndex))
			end
			d.WeirdoQueue = ""
		end
	end
end

-- A line on every screen (RoundService: A PHANTOM HAS ENTERED THE MATCH).
function DropService.Banner(text: string)
	dropEvent:FireAllClients({ kind = "Banner", text = text })
end

-- Round 1 setup (RoundService): uses one boost token, the one you hold most of. Returns the item to start with.
function DropService.TakeStartToken(player: Player): string?
	local d = DataService.Get(player)
	if not d then
		return nil
	end
	local best: string? = nil
	local bestCount = 0
	for item, count in d.Inventory.Boosts do
		if count > bestCount or (count == bestCount and best ~= nil and item < best) then
			best, bestCount = item, count
		end
	end
	local item = best
	if not item or bestCount <= 0 then
		return nil
	end
	if bestCount <= 1 then
		d.Inventory.Boosts[item] = nil
	else
		d.Inventory.Boosts[item] = bestCount - 1
	end
	DataService.Sync(player)
	return item
end

-- Studio (DebugService): a crate right now with this rarity, "Phantom" for the Phantom itself, a kind ("Card",
-- "Trail", "Horn": a random one of those) or a Pool Id.
function DropService.DebugDrop(player: Player, what: string)
	if not RunService:IsStudio() then
		return
	end
	if what == "Phantom" then
		open(player, 1, nil, "CarPhantom")
	elseif table.find(cfg.Rarities, what) then
		open(player, 1, what)
	elseif findPrize(what) then
		open(player, 1, nil, what)
	else
		local ofKind: { string } = {}
		for _, entry in cfg.Pool do
			if entry.Kind == what then
				table.insert(ofKind, entry.Id)
			end
		end
		if #ofKind > 0 then
			open(player, 1, nil, ofKind[rng:NextInteger(1, #ofKind)])
		end
	end
end

-- Studio: `count` Bronze crates in a row with no reveals (pity shows up in the log), then one revealed.
function DropService.DebugBurst(player: Player, count: number)
	if not RunService:IsStudio() then
		return
	end
	for _ = 1, math.max(0, count - 1) do
		open(player, #cfg.TierByPlace + 1, nil, nil, true)
	end
	open(player, #cfg.TierByPlace + 1)
end

-- Studio: set the pity counter (29 makes the next natural drop an Epic or better).
function DropService.DebugSetPity(player: Player, count: number)
	local d = DataService.Get(player)
	if not RunService:IsStudio() or not d then
		return
	end
	d.PityCounter = math.clamp(math.floor(count), 0, cfg.PityEpic)
	DataService.Sync(player)
	print(string.format("[DropService] %s pity set to %d", player.Name, d.PityCounter))
end

function DropService.Init()
	dropEvent = Remotes.Get("DropEvent")
end

function DropService.Start() end

return DropService
