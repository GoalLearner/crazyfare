--!strict
-- The weekly live-event schedule (Config.Events), worked out the same way on the server (multipliers) and the client
-- (the HUD line). Times are Unix seconds (UTC): os.time() on the server, workspace:GetServerTimeNow() on clients.

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local Events = {}

local DAY = 86400
local WEEK = 7 * DAY

-- Sunday 00:00 UTC of the week holding t.
local function weekStart(t: number): number
	local days = math.floor(t / DAY)
	local weekday = (days + 4) % 7 -- 1970-01-01 was a Thursday; 0 = Sunday
	return (days - weekday) * DAY
end

local function windowStart(entry: Config.EventWindow, week: number): number
	return week + (entry.Day - 1) * DAY + entry.HourUtc * 3600
end

-- The event running at t: its kind id and when it ends, or nil. In Studio the Debug panel can pretend one is live.
function Events.Live(t: number): (string?, number)
	if RunService:IsStudio() then
		local pretend = workspace:GetAttribute(Config.Events.DebugAttribute)
		if typeof(pretend) == "string" and Config.Events.Kinds[pretend] then
			return pretend, t + 3600
		end
	end
	local week = weekStart(t)
	for _, entry in Config.Events.Weekly do
		for _, offset in { 0, -WEEK } do -- last week's window may run past Sunday 00:00
			local s = windowStart(entry, week + offset)
			local e = s + entry.Hours * 3600
			if t >= s and t < e then
				return entry.Kind, e
			end
		end
	end
	return nil, 0
end

-- The next event to start after t: its kind id and start time, or nil when the schedule is empty.
function Events.Next(t: number): (string?, number)
	local week = weekStart(t)
	local bestKind: string? = nil
	local bestAt = math.huge
	for _, entry in Config.Events.Weekly do
		local s = windowStart(entry, week)
		if s <= t then
			s += WEEK
		end
		if s < bestAt then
			bestAt = s
			bestKind = entry.Kind
		end
	end
	return bestKind, if bestKind then bestAt else 0
end

local function liveKind(t: number): Config.EventKindDef?
	local kind = Events.Live(t)
	return if kind then Config.Events.Kinds[kind] else nil
end

-- Golden Fares roll this many times as often while an event says so.
function Events.GoldenChanceMult(t: number): number
	local def = liveKind(t)
	return if def then def.GoldenChanceMult else 1
end

-- Match Gems are multiplied by this.
function Events.GemMult(t: number): number
	local def = liveKind(t)
	return if def then def.GemMult else 1
end

return Events
