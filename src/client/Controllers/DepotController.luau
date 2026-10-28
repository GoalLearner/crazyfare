--!strict
-- The Taxi Depot's board on your screen (only while you're in the depot): NEXT MATCH IN 0:08 (or WAITING FOR DRIVERS),
-- the next match's seats filling with people then bots, and STAY IN DEPOT / JOIN THE MATCH. Whether you're in the line-up
-- comes from the server's slots (RoundState), so the button always tells the truth. Config.Depot.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local DepotController = {}

local localPlayer = Players.LocalPlayer
local panel: Frame
local title: TextLabel
local slotRow: Frame
local choiceButton: TextButton
local inLineup = true -- the server's slots list you for the next match
local choiceRemote: RemoteEvent

local SLOT_WIDTH = 78 -- px per seat chip (layout, not gameplay)

local function between(phase: string): boolean
	return phase == "Waiting" or phase == "MatchEnd"
end

local function drawSlots(round: Types.RoundStatePayload)
	for _, child in slotRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local slots = round.slots
	local seats = round.maxDrivers or Config.Server.MaxDrivers
	slotRow.Visible = slots ~= nil
	if not slots then
		return
	end
	inLineup = false
	for i = 1, seats do
		local slot = slots[i]
		local you = slot ~= nil and slot.id == localPlayer.UserId
		if you then
			inLineup = true
		end
		local chip = UI.Frame({
			Size = UDim2.fromOffset(SLOT_WIDTH - 4, 26),
			BackgroundColor3 = if you then Config.PlayerFare.Color elseif slot and slot.bot then Color3.fromRGB(60, 60, 72) elseif slot then Color3.fromRGB(40, 110, 70) else Color3.fromRGB(30, 30, 38),
			BackgroundTransparency = if slot then 0 else 0.4,
			LayoutOrder = i,
		}, slotRow)
		UI.Corner(6, chip)
		local text = if slot and slot.bot then Config.Depot.SlotBot .. " " .. slot.name elseif slot then string.upper(slot.name) else Config.Depot.SlotOpen
		UI.Label({ Position = UDim2.fromOffset(4, 3), Size = UDim2.new(1, -8, 1, -6), Text = text, TextColor3 = if you then UI.Black elseif slot then UI.White else UI.Muted, Font = UI.FontMedium }, chip)
	end
end

local function styleButton(phase: string)
	-- in the line-up: you can sit it out; not in it (you chose to stay, or a match is running): you can join
	local canStay = between(phase) and inLineup
	choiceButton.Text = if canStay then Config.Depot.StayButton else Config.Depot.JoinButton
	choiceButton.BackgroundColor3 = if canStay then Color3.fromRGB(60, 70, 90) else Color3.fromRGB(60, 140, 80)
end

local function onRound(round: Types.RoundStatePayload)
	drawSlots(round)
	styleButton(round.phase)
end

local function refresh()
	panel.Visible = State.sessionState == "Depot"
	local round = State.round
	if round then
		onRound(round)
	end
end

local function build()
	local screen = UI.Screen("CrazyFareDepot", 11)
	local seats = Config.Server.MaxDrivers
	panel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(seats * SLOT_WIDTH + 24, 118), BackgroundTransparency = 0.15, Visible = false }, screen)
	UI.Corner(12, panel)
	UI.OnFit(function()
		panel.Position = UDim2.new(0.5, 0, 0, UI.BelowTopbar(16))
	end)
	title = UI.Label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 30), Text = "" }, panel)
	slotRow = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 42), Size = UDim2.fromOffset(seats * SLOT_WIDTH, 26), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, slotRow)
	choiceButton = UI.New("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(200, 34),
		BackgroundColor3 = Color3.fromRGB(60, 70, 90),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = Config.Depot.StayButton,
	}, panel) :: TextButton
	UI.Corner(8, choiceButton)
	choiceButton.Activated:Connect(function()
		local staying = choiceButton.Text == Config.Depot.StayButton
		choiceRemote:FireServer(if staying then "stay" else "join")
	end)
end

function DepotController.Init()
	choiceRemote = Remotes.Get("DepotChoice")
	build()
	State.RoundChanged:Connect(onRound)
	State.SessionChanged:Connect(refresh)
	refresh()
end

function DepotController.Start()
	RunService.RenderStepped:Connect(function()
		if not panel.Visible then
			return
		end
		local round = State.round
		local phase = State.GetPhase()
		if round and between(phase) and round.endsAt > 0 then
			-- the depot's countdown, or the podium's: either way the next match starts then
			local left = math.max(0, math.ceil(round.endsAt - workspace:GetServerTimeNow()))
			title.Text = string.format(Config.Depot.NextMatch, left // 60, left % 60)
			title.TextColor3 = UI.Cash
		elseif phase == "Waiting" then
			title.Text = Config.Depot.WaitingFor
			title.TextColor3 = UI.Muted
		else
			title.Text = Config.Depot.MatchRunning
			title.TextColor3 = UI.Warn
		end
	end)
end

return DepotController
