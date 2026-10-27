--!strict
-- Player level (XP per match) and the login streak. Both live in the profile (DataService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)

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
			entry.xp = xp
			entry.levelUp = ProgressionService.AddXp(player, xp)
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
	DataService.AddGems(player, reward)
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
