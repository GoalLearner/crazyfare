--!strict
-- Player level (XP per match) and the login streak. Both live in the profile (DataService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local Metrics = require(script.Parent.Parent.Metrics)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)

local ProgressionService = {}

local onNotice: Signal.Signal<Player, string> = Signal.new()
ProgressionService.OnNotice = onNotice -- (player, text) one-shot messages for the HUD

-- XP needed to go from `level` to `level + 1`.
function ProgressionService.XpForLevel(level: number): number
	return Config.Progression.LevelBaseXp + (level - 1) * Config.Progression.LevelStepXp
end

-- Adds XP, levels up as many times as it takes, returns (xpGained, leveledUp).
function ProgressionService.AddXp(player: Player, amount: number): boolean
	local d = DataService.Get(player)
	if not d or amount <= 0 then
		return false
	end
	d.Xp += amount
	local leveled = false
	while d.Level < Config.Progression.MaxLevel and d.Xp >= ProgressionService.XpForLevel(d.Level) do
		d.Xp -= ProgressionService.XpForLevel(d.Level)
		d.Level += 1
		leveled = true
	end
	if leveled then
		player:SetAttribute("Level", d.Level)
		onNotice:Fire(player, string.format("LEVEL %d", d.Level))
		Metrics.Level(player, d.Level)
	end
	DataService.Sync(player)
	return leveled
end

-- Match end: XP by placement and fares, written into the podium entries.
function ProgressionService.AwardMatch(results: { Types.PodiumEntry })
	local cfg = Config.Progression
	local contested = #results >= 2 -- no rivals, no placement bonus
	for i, entry in results do
		local byPlace = if contested then cfg.PlacementXp[math.min(i, #cfg.PlacementXp)] or 0 else 0
		local xp = cfg.MatchBaseXp + entry.fares * cfg.XpPerFare + byPlace
		local player = game:GetService("Players"):GetPlayerByUserId(entry.id) -- nil for a bot
		if player then
			if MonetizationService.HasPass(player, "DoubleXp") then
				xp *= Config.Monetization.DoubleXpMult
			end
			entry.xp = xp
			entry.levelUp = ProgressionService.AddXp(player, xp)
		end
	end
end

-- The grade a total earns against a threshold list (Config.License.Race / .Arcade): an index into Grades.
function ProgressionService.LicenseIndex(cents: number, thresholds: { number }): number
	local index = 1
	for i, dollars in thresholds do
		if cents >= dollars * 100 then
			index = i
		end
	end
	return index
end

-- Match end: each person's license for the match goes into their podium entry; a better one than ever is saved.
function ProgressionService.AwardLicense(results: { Types.PodiumEntry })
	for _, entry in results do
		local player = game:GetService("Players"):GetPlayerByUserId(entry.id)
		local d = if player then DataService.Get(player) else nil
		if not player or not d then
			continue
		end
		local index = ProgressionService.LicenseIndex(entry.cash, Config.License.Race)
		entry.license = Config.License.Grades[index]
		if index > d.BestLicense then
			entry.newBest = d.BestLicense > 0 -- the very first license isn't a "new best"
			d.BestLicense = index
			DataService.Sync(player)
		end
	end
end

-- Arcade end: the run's grade into the entry; a run better than ever is saved (and flagged), and so is a better grade.
function ProgressionService.AwardArcade(results: { Types.PodiumEntry })
	for _, entry in results do
		local player = game:GetService("Players"):GetPlayerByUserId(entry.id)
		local d = if player then DataService.Get(player) else nil
		if not player or not d then
			continue
		end
		local index = ProgressionService.LicenseIndex(entry.cash, Config.License.Arcade)
		entry.license = Config.License.Grades[index]
		local changed = false
		if entry.cash > d.ArcadeBest then
			entry.newBest = d.ArcadeBest > 0
			d.ArcadeBest = entry.cash
			changed = true
		end
		if index > d.ArcadeBestLicense then
			d.ArcadeBestLicense = index
			changed = true
		end
		if changed then
			DataService.Sync(player)
		end
	end
end

local function utcDay(): number
	return math.floor(os.time() / 86400)
end

-- First join of a UTC day extends or restarts the streak and pays it.
local function checkStreak(player: Player)
	local d = DataService.Get(player)
	if not d then
		return
	end
	local today = utcDay()
	if d.Streak.LastDay == today then
		return
	end
	if d.Streak.LastDay == today - 1 then
		d.Streak.Days += 1
	else
		d.Streak.Days = 1
	end
	d.Streak.LastDay = today
	local reward = Config.Streak.PerDay * math.min(d.Streak.Days, Config.Streak.MaxDays)
	DataService.AddGems(player, reward, "TimedReward", "Streak")
	onNotice:Fire(player, string.format("DAY %d STREAK  +%d GEMS", d.Streak.Days, reward))
end

function ProgressionService.GetStreakDays(player: Player): number
	local d = DataService.Get(player)
	return if d then d.Streak.Days else 0
end

function ProgressionService.Init()
	DataService.OnLoaded:Connect(function(player: Player)
		local d = DataService.Get(player)
		if d then
			player:SetAttribute("Level", d.Level)
		end
		-- Let the client boot before the streak toast.
		task.delay(3, checkStreak, player)
	end)
end

function ProgressionService.Start() end

return ProgressionService
