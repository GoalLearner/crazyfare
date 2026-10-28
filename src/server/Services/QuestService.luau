--!strict
-- Daily (3) and weekly (1) quests. Rolled from Config pools per UTC day / ISO week, progress stored in the profile,
-- Gems paid the moment a quest completes. Other services report progress through QuestService.Progress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Racers = require(script.Parent.Parent.Racers)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local FareService = require(script.Parent.FareService)
local PassengerService = require(script.Parent.PassengerService)
local ItemService = require(script.Parent.ItemService)
local ComboService = require(script.Parent.ComboService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local SessionService = require(script.Parent.SessionService)

type StoredQuest = { id: string, goal: number, progress: number, reward: number, done: boolean }
type QuestBook = {
	DailyKey: string?,
	Daily: { StoredQuest }?,
	WeeklyKey: string?,
	Weekly: StoredQuest?,
}

local QuestService = {}

local rng = Random.new()
local questEvent: RemoteEvent
local pendingNotice: { [Player]: string } = {}

local DAY = 86400
local WEEK = 7 * DAY
local WEEK_OFFSET = 4 * DAY -- 1970-01-01 was a Thursday; shift so weeks start on Monday 00:00 UTC

local function dayKey(): string
	return tostring(math.floor(os.time() / DAY))
end

local function weekKey(): string
	return "w" .. tostring(math.floor((os.time() - WEEK_OFFSET) / WEEK))
end

local function secondsToDayReset(): number
	return DAY - os.time() % DAY
end

local function secondsToWeekReset(): number
	return WEEK - (os.time() - WEEK_OFFSET) % WEEK
end

local function defText(id: string, pool: { Config.QuestDef }): Config.QuestDef?
	for _, def in pool do
		if def.Id == id then
			return def
		end
	end
	return nil
end

local function rollDaily(): { StoredQuest }
	local pool = table.clone(Config.Quests.DailyPool)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local quests: { StoredQuest } = {}
	for i = 1, math.min(Config.Quests.DailyCount, #pool) do
		local def = pool[i]
		table.insert(quests, { id = def.Id, goal = def.Goal, progress = 0, reward = def.Reward, done = false })
	end
	return quests
end

local function rollWeekly(): StoredQuest
	local def = Config.Quests.WeeklyPool[rng:NextInteger(1, #Config.Quests.WeeklyPool)]
	return { id = def.Id, goal = def.Goal, progress = 0, reward = def.Reward, done = false }
end

-- Ensures the profile's quest book is for today / this week; rolls fresh ones when it is not.
local function book(player: Player): QuestBook?
	local d = DataService.Get(player)
	if not d then
		return nil
	end
	local q = d.Quests :: QuestBook
	if q.DailyKey ~= dayKey() or not q.Daily then
		q.DailyKey = dayKey()
		q.Daily = rollDaily()
	end
	if q.WeeklyKey ~= weekKey() or not q.Weekly then
		q.WeeklyKey = weekKey()
		q.Weekly = rollWeekly()
	end
	return q
end

local function toEntry(stored: StoredQuest, pool: { Config.QuestDef }): Types.QuestEntry
	local def = defText(stored.id, pool)
	return {
		id = stored.id,
		text = if def then string.format(def.Text, stored.goal) else stored.id,
		goal = stored.goal,
		progress = math.min(stored.progress, stored.goal),
		reward = stored.reward,
		done = stored.done,
	}
end

function QuestService.Sync(player: Player)
	local q = book(player)
	if not q then
		return
	end
	local daily: { Types.QuestEntry } = {}
	for _, stored in q.Daily :: { StoredQuest } do
		table.insert(daily, toEntry(stored, Config.Quests.DailyPool))
	end
	local payload: Types.QuestPayload = {
		daily = daily,
		weekly = if q.Weekly then toEntry(q.Weekly :: StoredQuest, Config.Quests.WeeklyPool) else nil,
		streakDays = ProgressionService.GetStreakDays(player),
		dailyResetsIn = secondsToDayReset(),
		weeklyResetsIn = secondsToWeekReset(),
		notice = pendingNotice[player],
	}
	pendingNotice[player] = nil
	questEvent:FireClient(player, payload)
end

local function advance(player: Player, stored: StoredQuest, amount: number, label: string): boolean
	if stored.done then
		return false
	end
	stored.progress += amount
	if stored.progress >= stored.goal then
		stored.done = true
		DataService.AddGems(player, stored.reward, "Gameplay", "Quest:" .. stored.id)
		pendingNotice[player] = string.format("%s QUEST DONE  +%d GEMS", label, stored.reward)
		return true
	end
	return false
end

-- Report progress on a quest id for a player. Quietly ignored when they have no such quest.
function QuestService.Progress(player: Player, questId: string, amount: number)
	local q = book(player)
	if not q or amount <= 0 then
		return
	end
	local changed = false
	for _, stored in q.Daily :: { StoredQuest } do
		if stored.id == questId then
			advance(player, stored, amount, "DAILY")
			changed = true
		end
	end
	local weekly = q.Weekly
	if weekly and weekly.id == questId then
		advance(player, weekly, amount, "WEEKLY")
		changed = true
	end
	if changed then
		QuestService.Sync(player)
	end
end

function QuestService.OnMatchEnd(results: { Types.PodiumEntry })
	for i, entry in results do
		local player = Players:GetPlayerByUserId(entry.id)
		if not player then
			continue
		end
		if i == 1 then
			QuestService.Progress(player, "wins", 1)
		end
		if i <= 2 then
			QuestService.Progress(player, "top2", 1)
		end
	end
end

function QuestService.Init()
	questEvent = Remotes.Get("QuestSync")
	DataService.OnLoaded:Connect(function(player: Player)
		QuestService.Sync(player)
	end)
	ProgressionService.OnNotice:Connect(function(player: Player, text: string)
		pendingNotice[player] = text
		QuestService.Sync(player)
	end)
	SessionService.OnNotice:Connect(function(player: Player, text: string)
		pendingNotice[player] = text
		QuestService.Sync(player)
	end)
	Remotes.Get("ClientReady").OnServerEvent:Connect(function(player: Player)
		if DataService.IsLoaded(player) then
			QuestService.Sync(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pendingNotice[player] = nil
	end)

	-- Progress sources
	FareService.OnDelivered:Connect(function(player: Player, tier: string, tip: number)
		if Racers.IsBot(player) then
			return
		end
		QuestService.Progress(player, "deliver", 1)
		if tier == "Red" then
			QuestService.Progress(player, "red", 1)
		end
		if tip > 0 then
			QuestService.Progress(player, "tips", tip / 100) -- tips arrive in cents; the quest counts dollars
			LeaderboardService.ReportTip(player, tip)
		end
	end)
	PassengerService.OnBailed:Connect(function(_victim: Player, _npc: PassengerService.Npc, reason: string, attacker: Player?)
		if reason == "hp" and attacker and not Racers.IsBot(attacker) then
			QuestService.Progress(attacker, "knockouts", 1)
			DataService.AddStat(attacker, "Knockouts", 1)
			LeaderboardService.AddKnockout(attacker)
		end
	end)
	ItemService.OnTomatoHit:Connect(function(attacker: Player)
		if Racers.IsBot(attacker) then
			return
		end
		QuestService.Progress(attacker, "tomato", 1)
	end)
	ComboService.OnDrift:Connect(function(player: Player, seconds: number)
		QuestService.Progress(player, "drift", seconds)
	end)
end

function QuestService.Start() end

return QuestService
