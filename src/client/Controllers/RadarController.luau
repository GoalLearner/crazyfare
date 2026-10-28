--!strict
-- Fare Radar (a Robux pass, Config.Monetization.Radar): while you drive a round with nobody aboard, a beacon floats
-- over every waiting Golden and long (Red) fare, seen through buildings from anywhere on the map. The beacons are this
-- client's own BillboardGuis (in PlayerGui, adorned to the passengers), so nobody else sees them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local RadarController = {}

local localPlayer = Players.LocalPlayer
local cfg = Config.Monetization.Radar
local folder: Folder
local beacons: { [Model]: BillboardGui } = {}
local checkAt = 0

local function makeBeacon(model: Model, golden: boolean): BillboardGui?
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not anchor then
		return nil
	end
	local color = if golden then Config.Golden.Color else Config.Fares.Tiers.Red.Color
	local gui = UI.New("BillboardGui", {
		Adornee = anchor,
		Size = UDim2.fromOffset(cfg.Size, cfg.Size),
		StudsOffset = Vector3.new(0, cfg.Lift, 0),
		SizeOffset = Vector2.new(0, cfg.RaiseBySize),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = math.huge,
	}, folder) :: BillboardGui
	local dot = UI.Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 0.15 }, gui)
	UI.Corner(cfg.Size // 2, dot)
	UI.Stroke(UI.White, 3, dot)
	UI.Label({ Size = UDim2.fromScale(1, 1), Text = if golden then cfg.GoldenText else cfg.LongText, TextColor3 = UI.White }, dot)
	return gui
end

local function refresh()
	local on = localPlayer:GetAttribute("Pass_FareRadar") == true
		and State.sessionState == "Driver"
		and State.fare == nil
		and State.GetPhase() == "Playing"
	local wanted: { [Model]: boolean } = {}
	if on then
		for _, inst in CollectionService:GetTagged(Config.Tags.Npc) do
			if inst:IsA("Model") and inst:IsDescendantOf(workspace) then
				local golden = inst:GetAttribute("Golden") == true
				local owner = inst:GetAttribute("ReservedFor")
				local revealAt = inst:GetAttribute("RevealAt")
				local hidden = typeof(owner) == "number" and owner ~= localPlayer.UserId and typeof(revealAt) == "number" and workspace:GetServerTimeNow() < revealAt
				if (golden or inst:GetAttribute("Tier") == "Red") and not hidden then
					wanted[inst] = true
					if not beacons[inst] then
						local gui = makeBeacon(inst, golden)
						if gui then
							beacons[inst] = gui
						end
					end
				end
			end
		end
	end
	for model, gui in beacons do
		if not wanted[model] then
			gui:Destroy()
			beacons[model] = nil
		end
	end
end

function RadarController.Init()
	folder = Instance.new("Folder")
	folder.Name = "CrazyFareRadar"
	folder.Parent = localPlayer:WaitForChild("PlayerGui")
end

function RadarController.Start()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= checkAt then
			checkAt = now + cfg.CheckSeconds
			refresh()
		end
	end)
end

return RadarController
