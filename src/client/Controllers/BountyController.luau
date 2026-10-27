--!strict
-- The bounty crown (Config.Chaos.Bounty): hangs over the cash leader's cab for everyone else to hunt, seen from
-- anywhere and through buildings. Your own crown stays off your screen (the minimap and the banner tell you).
-- Driven by the snapshot's `bounty` (the leader's UserId).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local BountyController = {}

local crown: BillboardGui
local wearer = 0 -- UserId the crown is on (0 = nobody)

local function findVehicle(userId: number): Model?
	for _, inst in CollectionService:GetTagged(Config.Tags.Vehicle) do
		if inst:IsA("Model") and inst:GetAttribute("OwnerUserId") == userId and inst:IsDescendantOf(workspace) then
			return inst
		end
	end
	return nil
end

local function onSnapshot(snapshot: Types.Snapshot)
	local leader = snapshot.bounty or 0
	if leader == Players.LocalPlayer.UserId then
		leader = 0
	end
	local model = if leader ~= 0 then findVehicle(leader) else nil
	local chassis = if model then model.PrimaryPart else nil
	if not chassis then
		crown.Enabled = false
		wearer = 0
		return
	end
	if wearer ~= leader or crown.Adornee ~= chassis then
		wearer = leader
		crown.Adornee = chassis
	end
	crown.Enabled = true
end

function BountyController.Init()
	local cfg = Config.Chaos.Bounty
	crown = UI.New("BillboardGui", {
		Name = "BountyCrown",
		Size = UDim2.fromOffset(cfg.CrownSize, cfg.CrownSize),
		StudsOffsetWorldSpace = Vector3.new(0, cfg.CrownHeight, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
	}, Players.LocalPlayer:WaitForChild("PlayerGui")) :: BillboardGui
	UI.Label({ Size = UDim2.fromScale(1, 1), Text = cfg.Crown, TextColor3 = cfg.Color, TextStrokeTransparency = 0.3 }, crown)
	State.SnapshotReceived:Connect(onSnapshot)
end

function BountyController.Start() end

return BountyController
