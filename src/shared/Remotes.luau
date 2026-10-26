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
	-- client -> server
	"UseItem", -- ()
	"ComboEvent", -- (Types.ComboEventPayload)
	"DriveState", -- (drifting: boolean)
	"ResetVehicle", -- ()
	"ClientReady", -- () client booted; server replies with RoundState + VehicleAssigned
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
