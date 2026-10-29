--!strict
-- Studio-only soak test (Config.Soak). Set the workspace attribute (Config.Soak.Attribute) to true before Play and bots
-- fill every seat with nobody needing to drive (a client can sit on the title screen, which counts nowhere). Every
-- phase change, round, match and odd car (stuck, flipped, fallen) prints a "[Soak]" line, and each match end prints the
-- server's memory, frame rate and instance counts, so a long unattended run can be read back from the Studio log file.
-- Off (does nothing) without the attribute.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Racers = require(script.Parent.Parent.Racers)
local Services = script.Parent.Parent.Services
local FareService = require(Services.FareService)
local ItemService = require(Services.ItemService)
local MatchController = require(Services.MatchController)
local PassengerService = require(Services.PassengerService)
local RoundService = require(Services.RoundService)
local VehicleService = require(Services.VehicleService)

local SoakMonitor = {}

local cfg = Config.Soak
local active = false

type Track = { pos: Vector3, since: number, stuckSaid: boolean, flipSince: number?, flipSaid: boolean, fallSaid: boolean }
type Tally = { claims: number, deliveries: number, bails: number, timeouts: number, tomatoes: number, stuck: number, bot: boolean }

local tracks: { [any]: Track } = {}
local tallies: { [string]: Tally } = {}
local cashBy: { [string]: { [string]: number } } = {} -- this round's AddCash by driver, then by the line that paid it
local claimed: { [string]: { trip: number, seconds: number, destination: Vector3 } } = {}
-- what each FareService.AddCash caller pays for (anything else shows as its script:line)
local CASH_SOURCES: { [string]: string } = {
	["FareService:518"] = "stunts",
	["FareService:664"] = "fares",
	["FareService:734"] = "rider tips",
	["FareService:764"] = "hunter",
	["WorldEventService:412"] = "coins",
}
local phase = ""
local phaseAt = 0
local matches = 0
local frames, frameTime, hitches, worstFrame = 0, 0, 0, 0
local startMemory = 0

local function say(text: string)
	print("[Soak] " .. text)
end

local function nameOf(driver: any): string
	return tostring(driver.DisplayName or driver.Name or "?")
end

local function tally(driver: any): Tally
	local name = nameOf(driver)
	local existing = tallies[name]
	if existing then
		return existing
	end
	local fresh: Tally = { claims = 0, deliveries = 0, bails = 0, timeouts = 0, tomatoes = 0, stuck = 0, bot = Racers.IsBot(driver) }
	tallies[name] = fresh
	return fresh
end

local function money(cents: number): string
	return string.format("$%.2f", cents / 100)
end

-- One line per driver for the round just played; a driver who delivered nothing in a whole round is called out.
local function roundReport(round: number)
	local parts: { string } = {}
	for name, t in tallies do
		table.insert(parts, string.format("%s %d/%d (bails %d, timeouts %d, tomatoes %d, stuck %d)", name, t.deliveries, t.claims, t.bails, t.timeouts, t.tomatoes, t.stuck))
		if t.deliveries == 0 and t.bot then
			say(string.format("IDLE %s delivered nothing in round %d (%d pickups)", name, round, t.claims))
		end
	end
	table.sort(parts)
	say(string.format("round %d deliveries/pickups: %s", round, table.concat(parts, "; ")))
	table.clear(tallies)
	local cashParts: { string } = {}
	for name, sources in cashBy do
		local bits: { string } = {}
		for source, cents in sources do
			table.insert(bits, string.format("%s %s", source, money(cents)))
		end
		table.sort(bits)
		table.insert(cashParts, string.format("%s [%s]", name, table.concat(bits, ", ")))
	end
	table.sort(cashParts)
	say(string.format("round %d cash sources: %s", round, table.concat(cashParts, "; ")))
	table.clear(cashBy)
end

local function healthReport()
	local avg = if frames > 0 then frames / frameTime else 0
	local memory = Stats:GetTotalMemoryUsageMb()
	say(string.format(
		"health after match %d: memory %.0f MB (start %.0f, %+.0f), avg %.0f fps, %d hitches, worst frame %.0f ms, workspace %d instances, %d cars, %d npcs, %d traffic",
		matches,
		memory,
		startMemory,
		memory - startMemory,
		avg,
		hitches,
		worstFrame * 1000,
		#workspace:GetDescendants(),
		#CollectionService:GetTagged(Config.Tags.Vehicle),
		#CollectionService:GetTagged(Config.Tags.Npc),
		#CollectionService:GetTagged(Config.Tags.Traffic)
	))
	frames, frameTime, hitches, worstFrame = 0, 0, 0, 0
end

-- Stuck, flipped or fallen cars while racing (anchored cars are on the grid or in a pit stop).
local function sampleCars()
	local t = os.clock()
	local seen: { [any]: boolean } = {}
	for driver, entry in VehicleService.GetAll() do
		local chassis = entry.chassis
		if chassis.Anchored or not chassis:IsDescendantOf(workspace) then
			continue
		end
		seen[driver] = true
		local pos = chassis.Position
		local track = tracks[driver]
		if not track then
			tracks[driver] = { pos = pos, since = t, stuckSaid = false, flipSince = nil, flipSaid = false, fallSaid = false }
			continue
		end
		local name = nameOf(driver)
		if (pos - track.pos).Magnitude > cfg.StuckStuds then
			if track.stuckSaid then
				say(string.format("%s moving again after %.0fs", name, t - track.since))
			end
			track.pos, track.since, track.stuckSaid = pos, t, false
		elseif not track.stuckSaid and t - track.since >= cfg.StuckSeconds then
			track.stuckSaid = true
			tally(driver).stuck += 1
			say(string.format("STUCK %s at (%.0f, %.0f) for %.0fs%s", name, pos.X, pos.Z, t - track.since, if FareService.GetFare(driver) then " carrying a fare" else ""))
		end
		if chassis.CFrame.UpVector.Y < cfg.FlipUpY then
			local since = track.flipSince or t
			track.flipSince = since
			if not track.flipSaid and t - since >= cfg.FlipSeconds then
				track.flipSaid = true
				say(string.format("FLIPPED %s at (%.0f, %.0f)", name, pos.X, pos.Z))
			end
		else
			track.flipSince, track.flipSaid = nil, false
		end
		if pos.Y < cfg.FallBelow and not track.fallSaid then
			track.fallSaid = true
			say(string.format("FELL %s at (%.0f, %.1f, %.0f)", name, pos.X, pos.Y, pos.Z))
		end
	end
	for driver in tracks do
		if not seen[driver] then
			tracks[driver] = nil
		end
	end
end

local function onPhase(payload: Types.RoundStatePayload)
	local now = workspace:GetServerTimeNow()
	local old = phase
	say(string.format("%s -> %s after %.0fs (round %d, map %s, weather %s)", if old == "" then "boot" else old, payload.phase, now - phaseAt, payload.round, payload.map or "?", payload.weather or "-"))
	if old == "Playing" then
		local played = now - phaseAt
		say(string.format("round %d ended by %s after %.0fs", payload.round, if played < Config.Round.CapSeconds - 1 then "QUOTA" else "time cap", played))
		roundReport(payload.round)
	end
	local results = payload.results
	if payload.phase == "RoundEnd" and results then
		local parts: { string } = {}
		for place, entry in results do
			table.insert(parts, string.format("%d %s %s %d fares", place, entry.name, money(entry.cash), entry.fares))
		end
		say(string.format("round %d standings (quota %s): %s", payload.round, money(payload.quota), table.concat(parts, "; ")))
	end
	phase, phaseAt = payload.phase, now
	table.clear(tracks)
end

function SoakMonitor.Init()
	active = RunService:IsStudio() and workspace:GetAttribute(cfg.Attribute) == true
	if not active then
		return
	end
	-- nobody needs to drive, and bots take every seat
	Config.Round.StudioMinPlayers = 0
	Config.Bots.MinHumans = 0
	Config.Server.BotFillTo = math.min(cfg.Seats, Config.Server.MaxDrivers)
	say(string.format("on: bots fill %d seats, no person needed", Config.Server.BotFillTo))
	-- every cash credit, by who paid it (FareService.AddCash is always called through the table, so this sees them all)
	local addCash = FareService.AddCash
	FareService.AddCash = function(player: Player, amount: number)
		local source, line = debug.info(2, "sl")
		local key = string.format("%s:%d", string.match(tostring(source), "([%w_]+)$") or "?", line or 0)
		local sources = cashBy[nameOf(player)] or {}
		cashBy[nameOf(player)] = sources
		local label = CASH_SOURCES[key] or key
		sources[label] = (sources[label] or 0) + amount
		addCash(player, amount)
	end
	FareService.OnClaimed:Connect(function(driver: Player)
		tally(driver).claims += 1
		local fare = FareService.GetFare(driver)
		if fare then
			claimed[nameOf(driver)] = { trip = fare.distance, seconds = fare.deadline - fare.startedAt, destination = fare.destination }
		end
	end)
	FareService.OnDelivered:Connect(function(driver: Player)
		tally(driver).deliveries += 1
	end)
	PassengerService.OnBailed:Connect(function(victim: Player, _npc: any, reason: string)
		local t = tally(victim)
		if reason == "timeout" then
			t.timeouts += 1
			local trip = claimed[nameOf(victim)]
			local entry = VehicleService.GetEntry(victim)
			if trip and entry then
				local left = (Vector3.new(trip.destination.X, 0, trip.destination.Z) - Vector3.new(entry.chassis.Position.X, 0, entry.chassis.Position.Z)).Magnitude
				say(string.format("TIMEOUT %s: %.0f stud trip, %.1fs timer, %.0f studs still to go", nameOf(victim), trip.trip, trip.seconds, left))
			end
		else
			t.bails += 1
		end
	end)
	ItemService.OnTomatoHit:Connect(function(attacker: Player)
		tally(attacker).tomatoes += 1
	end)
	MatchController.OnMatchEnded:Connect(function(results: { Types.PodiumEntry })
		matches += 1
		local parts: { string } = {}
		for place, entry in results do
			table.insert(parts, string.format("%d %s %s %d fares", place, entry.name, money(entry.cash), entry.fares))
		end
		say(string.format("match %d over: %s", matches, table.concat(parts, "; ")))
		healthReport()
	end)
end

function SoakMonitor.Start()
	if not active then
		return
	end
	startMemory = Stats:GetTotalMemoryUsageMb()
	local nextPoll, nextSample = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		frames += 1
		frameTime += dt
		worstFrame = math.max(worstFrame, dt)
		if dt > cfg.HitchSeconds then
			hitches += 1
			if dt > cfg.BigHitchSeconds then
				say(string.format("HITCH %.0f ms during %s", dt * 1000, phase))
			end
		end
		local t = os.clock()
		if t < nextPoll then
			return
		end
		nextPoll = t + cfg.PollSeconds
		local payload = RoundService.GetPayload()
		if payload.phase ~= phase then
			onPhase(payload)
		elseif payload.endsAt > 0 and workspace:GetServerTimeNow() > payload.endsAt + cfg.PhaseSlack then
			say(string.format("OVERRUN %s is %.0fs past its end", phase, workspace:GetServerTimeNow() - payload.endsAt))
			phaseAt = workspace:GetServerTimeNow() -- once per PhaseSlack, not every poll
		end
		if phase == "Playing" and t >= nextSample then
			nextSample = t + cfg.SampleSeconds
			sampleCars()
		end
	end)
end

return SoakMonitor
