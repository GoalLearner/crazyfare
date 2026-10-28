--!strict
-- A Weirdo card's bonus fare (Config.Cosmetics.Bonus) is its owner's alone for the head start: on everyone else's
-- screen its badge and name tag stay hidden until RevealAt (the server can't hide a replicated BillboardGui for one
-- player, so each client does). The NPC model carries ReservedFor (UserId) and RevealAt (server time).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local WeirdoController = {}

local BADGES = { "Icon", "Card" } -- the BillboardGuis on the head that give it away

local localPlayer = Players.LocalPlayer

local function update()
	local now = workspace:GetServerTimeNow()
	for _, inst in CollectionService:GetTagged(Config.Tags.Npc) do
		local owner = inst:GetAttribute("ReservedFor")
		if typeof(owner) ~= "number" or owner == localPlayer.UserId then
			continue
		end
		local revealAt = inst:GetAttribute("RevealAt")
		local hidden = typeof(revealAt) == "number" and now < revealAt
		local head = inst:FindFirstChild("Head")
		if not head then
			continue
		end
		for _, name in BADGES do
			local gui = head:FindFirstChild(name)
			if gui and gui:IsA("BillboardGui") and gui.Enabled == hidden then
				gui.Enabled = not hidden
			end
		end
	end
end

function WeirdoController.Init() end

function WeirdoController.Start()
	RunService.Heartbeat:Connect(update)
end

return WeirdoController
