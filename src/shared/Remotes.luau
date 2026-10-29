--!strict
-- Every remote, defined once. Server creates them on first require; clients wait for them.
-- Adding one: add the name here AND a rate limit in Config.Net.RateLimits if the client fires it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENT_NAMES = {
	-- server -> client
	"Snapshot", -- batched 10 Hz world state (Types.Snapshot)
	"RoundState", -- phase changes (Types.RoundStatePayload)
	"FareEvent", -- claimed / delivered / bailed / taken (Types.FareEventPayload)
	"ItemEvent", -- granted / used / splat / spinout / boost (Types.ItemEventPayload)
	"VehicleAssigned", -- (model: Model)
	"PitStopOffer", -- (Types.PitStopOfferPayload)
	"ProfileSync", -- (Types.ProfilePayload) whenever the profile changes
	"QuestSync", -- (Types.QuestPayload) when quests, streak or progress change
	"LeaderboardSync", -- (Types.LeaderboardPayload) on request and on refresh
	"DropEvent", -- (Types.DropEventPayload) your post-match drop; a Mythic pull goes to everyone
	"MapVoteState", -- (Types.MapVoteStatePayload) the next-map vote opened, changed or closed
	"StreakEvent", -- (Types.StreakPayload) today's streak calendar prize was just paid
	-- client -> server
	"UseItem", -- ()
	"ComboEvent", -- (Types.ComboEventPayload)
	"DriveState", -- (drifting: boolean)
	"ResetVehicle", -- ()
	"ClientReady", -- () client booted; server replies with RoundState + VehicleAssigned
	"PitStopBuy", -- (cardId: string, undo: boolean?) undo hands a bought card back for a refund
	"PitStopReady", -- (ready: boolean) READY in the Pit Stop; all players ready ends it in Config.PitStop.ReadySeconds
	"GarageAction", -- (action: "Select" | "Buy" | "Upgrade" | "Paint" | "Trail" | "Horn", id: string)
	"RequestLeaderboards", -- ()
	"ShopAction", -- (action: "Refresh" | "DismissStarter")
	"CoachDone", -- () the first-match coach prompts have all been shown
	"ArcadeRequest", -- (action: "start" | "leave") solo Arcade: go there, or back to racing
	"HailCab", -- (hail: boolean) on foot at a curb: become a player fare, or call it off
	"RateRide", -- (stars: number) 1-5, after your ride arrived
	"DepotChoice", -- (choice: "stay" | "join") sit the next match out in the depot, or drive it
	"Play", -- () PLAY on the title screen: leave the menu for the depot, a seat or the sidewalk
	"SaveSettings", -- (settings: { music: number, sfx: number, shake: boolean, speedFx: boolean }) OPTIONS changed
	"MapVote", -- (map: string) your pick for the next map on the match-end podium
	"DailyBuy", -- (id: string) buy one of today's daily shop cosmetics for Gems (Config.DailyShop)
	"Debug", -- (command: string, arg: any) Studio only
}

local Remotes = {}

local folder: Folder

if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.Get(name: string): RemoteEvent
	local inst = folder:WaitForChild(name, 10)
	assert(inst and inst:IsA("RemoteEvent"), "Unknown remote: " .. name)
	return inst :: RemoteEvent
end

Remotes.Names = EVENT_NAMES

return Remotes
