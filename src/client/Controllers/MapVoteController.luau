--!strict
-- The next-map vote (Config.MapVote): a card right of the match-end podium with one button per map and its votes, your
-- pick outlined. Tapping sends MapVote; the server answers every change with MapVoteState, which redraws the counts.
-- Only during a race's MatchEnd while the vote is open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local MapVoteController = {}

local PODIUM_HALF = 210 -- HudController's podium is 420 wide and centered (the crate card sits on its left)

local cfg = Config.MapVote
local card: Frame
local list: Frame
local voteRemote: RemoteEvent
local current: Types.MapVoteStatePayload? = nil
local myVote = ""
local onPodium = false

local function mapLabel(name: string): string
	local mapCfg = (Config.Map :: any)[name]
	local display = if typeof(mapCfg) == "table" and typeof(mapCfg.DisplayName) == "string" then mapCfg.DisplayName else name
	return string.upper(display)
end

local function render()
	local state = current
	local show = onPodium and state ~= nil and state.open
	card.Visible = show
	if not state or not show then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for i, name in state.options do
		local mine = myVote == name
		local b = UI.New("TextButton", {
			Size = UDim2.new(1, 0, 0, cfg.RowHeight),
			LayoutOrder = i,
			BackgroundColor3 = if mine then Color3.fromRGB(60, 140, 80) else Color3.fromRGB(70, 110, 190),
			BorderSizePixel = 0,
			Font = UI.Font,
			TextSize = 17,
			TextColor3 = UI.White,
			Text = string.format("%s   %d", mapLabel(name), state.counts[name] or 0),
			AutoButtonColor = true,
		}, list) :: TextButton
		UI.Corner(8, b)
		UI.Stroke(if mine then UI.White else Color3.fromRGB(40, 40, 48), if mine then 3 else 1, b).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		b.Activated:Connect(function()
			if myVote ~= name then
				myVote = name
				voteRemote:FireServer(name)
				render()
			end
		end)
	end
	card.Size = UDim2.fromOffset(cfg.Width, 70 + #state.options * (cfg.RowHeight + 6))
end

local function build()
	local screen = UI.Screen("CrazyFareMapVote", 21)
	card = UI.Frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, PODIUM_HALF + 16, 0.5, 0),
		Size = UDim2.fromOffset(cfg.Width, 160),
		BackgroundTransparency = 0.1,
		Visible = false,
	}, screen)
	UI.Corner(14, card)
	UI.Label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 26), Text = cfg.Title, TextColor3 = UI.Accent }, card)
	list = UI.Frame({ Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 1, -64), BackgroundTransparency = 1 }, card)
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	UI.Label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -6), Size = UDim2.new(1, -24, 0, 16), Text = cfg.Hint, TextColor3 = UI.Muted, Font = UI.FontMedium, TextScaled = false, TextSize = 12 }, card)
end

function MapVoteController.Init()
	build()
	voteRemote = Remotes.Get("MapVote")
	Remotes.Get("MapVoteState").OnClientEvent:Connect(function(payload: Types.MapVoteStatePayload)
		local wasOpen = current ~= nil and current.open
		current = payload
		if payload.open and not wasOpen then
			myVote = "" -- a new podium, a new vote
		end
		render()
	end)
	State.RoundChanged:Connect(function(payload: Types.RoundStatePayload)
		onPodium = payload.phase == "MatchEnd" and payload.mode ~= "Arcade"
		render()
	end)
end

function MapVoteController.Start() end

return MapVoteController
