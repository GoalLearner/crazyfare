--!strict
-- Map voting (Config.MapVote): during a race's match-end podium every person can tap the next map. RoundService opens
-- the vote when the podium starts and takes the winner when the next match begins: most votes wins, and a tie that
-- includes the rotation's own pick (or no votes at all) keeps that pick. Bots never vote. Counts go to every client
-- on each change (MapVoteState).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Types = require(ReplicatedStorage.Shared.Types)

local MapVoteService = {}

local votes: { [Player]: string } = {}
local open = false
local stateEvent: RemoteEvent
local rng = Random.new()

local function counts(): { [string]: number }
	local tally: { [string]: number } = {}
	for _, name in Config.Map.Rotation do
		tally[name] = 0
	end
	for _, name in votes do
		tally[name] = (tally[name] or 0) + 1
	end
	return tally
end

local function broadcast()
	local payload: Types.MapVoteStatePayload = { open = open, options = Config.Map.Rotation, counts = counts() }
	stateEvent:FireAllClients(payload)
end

-- RoundService: a race's podium began; fresh votes.
function MapVoteService.Open()
	table.clear(votes)
	open = true
	broadcast()
end

-- RoundService: the next match is starting. Returns the map to load (`default` = the rotation's pick).
function MapVoteService.TakeWinner(default: string): string
	local wasOpen = open
	local tally = counts()
	open = false
	table.clear(votes)
	if wasOpen then
		broadcast()
	end
	local best = 0
	for _, n in tally do
		best = math.max(best, n)
	end
	if best == 0 then
		return default
	end
	local tied: { string } = {}
	for _, name in Config.Map.Rotation do
		if tally[name] == best then
			table.insert(tied, name)
		end
	end
	local winner = if table.find(tied, default) then default else tied[rng:NextInteger(1, #tied)]
	if RunService:IsStudio() then
		local parts: { string } = {}
		for _, name in Config.Map.Rotation do
			table.insert(parts, string.format("%s %d", name, tally[name] or 0))
		end
		print(string.format("[MapVoteService] %s -> %s", table.concat(parts, ", "), winner))
	end
	return winner
end

function MapVoteService.Init()
	stateEvent = Remotes.Get("MapVoteState")
	Remotes.Get("MapVote").OnServerEvent:Connect(function(player: Player, name: any)
		if not RateLimiter.Allow(player, "MapVote", Config.Net.RateLimits.MapVote) then
			return
		end
		if not open or typeof(name) ~= "string" or not table.find(Config.Map.Rotation, name) then
			return
		end
		if votes[player] == name then
			return
		end
		votes[player] = name
		broadcast()
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		if votes[player] then
			votes[player] = nil
			if open then
				broadcast()
			end
		end
	end)
end

function MapVoteService.Start() end

return MapVoteService
