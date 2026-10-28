--!strict
-- The Progress panel: level and XP, login streak, daily and weekly quests, and the four leaderboards.
-- Opens from a button under the garage button whenever a round is not running.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local ProgressController = {}

local openButton: TextButton
local panel: Frame
local levelLabel: TextLabel
local xpBar: UI.Bar
local xpLabel: TextLabel
local streakLabel: TextLabel
local questList: Frame
local questFooter: TextLabel
local boardsFrame: Frame
local isOpen = false
local requestBoards: RemoteEvent

local BOARD_ROWS = 5

local function formatDuration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	end
	return string.format("%dm", math.max(1, s // 60))
end

local function renderQuests(quests: Types.QuestPayload)
	for _, child in questList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local entries: { { entry: Types.QuestEntry, tag: string } } = {}
	for _, q in quests.daily do
		table.insert(entries, { entry = q, tag = "DAILY" })
	end
	if quests.weekly then
		table.insert(entries, { entry = quests.weekly, tag = "WEEKLY" })
	end
	for i, item in entries do
		local q = item.entry
		local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 54), LayoutOrder = i, BackgroundTransparency = if q.done then 0.2 else 0.45, BackgroundColor3 = if q.done then Color3.fromRGB(30, 50, 40) else UI.Panel }, questList)
		UI.Corner(8, row)
		UI.Label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(60, 14), Text = item.tag, TextColor3 = if item.tag == "WEEKLY" then UI.Warn else UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 11 }, row)
		UI.Label({ Position = UDim2.fromOffset(12, 20), Size = UDim2.new(1, -140, 0, 20), Text = q.text, TextXAlignment = Enum.TextXAlignment.Left, Font = UI.FontMedium, TextScaled = false, TextSize = 15 }, row)
		local bar = UI.Bar({ Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -140, 0, 5) }, if q.done then UI.Cash else UI.Accent, row)
		UI.SetBar(bar, if q.goal > 0 then q.progress / q.goal else 0)
		UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(110, 20), Text = if q.done then "DONE" else string.format("%d / %d", math.floor(q.progress), q.goal), TextColor3 = if q.done then UI.Cash else UI.White, TextXAlignment = Enum.TextXAlignment.Right, TextScaled = false, TextSize = 15 }, row)
		UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 30), Size = UDim2.fromOffset(110, 16), Text = string.format("+%d gems", q.reward), TextColor3 = UI.Accent, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Right, TextScaled = false, TextSize = 12 }, row)
	end
	questFooter.Text = string.format("Daily resets in %s  ·  Weekly board and quest reset in %s", formatDuration(quests.dailyResetsIn), formatDuration(quests.weeklyResetsIn))
	streakLabel.Text = if quests.streakDays > 0 then string.format("%d-DAY STREAK", quests.streakDays) else ""
end

local function renderBoard(parent: Frame, title: string, entries: { Types.BoardEntry }, money: boolean)
	for _, child in parent:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	UI.Label({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 18), Text = title, TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 12 }, parent)
	local me = game:GetService("Players").LocalPlayer.UserId
	for i = 1, BOARD_ROWS do
		local entry = entries[i]
		local y = 20 + (i - 1) * 16
		local isMe = entry ~= nil and entry.id == me
		UI.Label({ Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, -60, 0, 16), Text = if entry then string.format("%d  %s", i, entry.name) else string.format("%d  -", i), TextColor3 = if isMe then UI.Warn else UI.White, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 13 }, parent)
		UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, y), Size = UDim2.fromOffset(60, 16), Text = if entry then (if money then UI.Money(entry.value) else tostring(entry.value)) else "", TextColor3 = UI.Accent, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Right, TextScaled = false, TextSize = 13 }, parent)
	end
end

local function renderBoards(boards: Types.LeaderboardPayload)
	local weekly = boardsFrame:FindFirstChild("Weekly")
	local friends = boardsFrame:FindFirstChild("Friends")
	local tip = boardsFrame:FindFirstChild("BestTip")
	local ko = boardsFrame:FindFirstChild("Knockouts")
	local arcade = boardsFrame:FindFirstChild("Arcade")
	if weekly and weekly:IsA("Frame") then
		renderBoard(weekly, "THIS WEEK · GEMS", boards.weekly, false)
	end
	if friends and friends:IsA("Frame") then
		renderBoard(friends, "FRIENDS · THIS WEEK", boards.friends, false)
	end
	if tip and tip:IsA("Frame") then
		renderBoard(tip, "BIGGEST TIP EVER", boards.bestTip, true)
	end
	if ko and ko:IsA("Frame") then
		renderBoard(ko, "MOST KNOCKED OUT", boards.knockouts, false)
	end
	if arcade and arcade:IsA("Frame") then
		renderBoard(arcade, "BEST ARCADE RUN", boards.arcade or {}, true)
	end
end

local function render()
	local profile = State.profile
	if profile then
		levelLabel.Text = string.format("LEVEL %d", profile.level)
		UI.SetBar(xpBar, if profile.xpToNext > 0 then profile.xpIntoLevel / profile.xpToNext else 0)
		xpLabel.Text = string.format("%d / %d XP", profile.xpIntoLevel, profile.xpToNext)
	end
	if State.quests then
		renderQuests(State.quests :: Types.QuestPayload)
	end
	if State.boards then
		renderBoards(State.boards :: Types.LeaderboardPayload)
	end
end

local function setOpen(open: boolean)
	isOpen = open
	panel.Visible = open
	if open then
		render()
		requestBoards:FireServer()
	end
end

local function build()
	local screen = UI.Screen("CrazyFareProgress", 17)
	openButton = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 24 + Config.Hud.MinimapSize + 10 + 34 + 8),
		Size = UDim2.fromOffset(Config.Hud.MinimapSize, 34),
		BackgroundColor3 = Color3.fromRGB(40, 44, 56),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = "QUESTS",
		Visible = false,
	}, screen) :: TextButton
	UI.Corner(8, openButton)
	openButton.Activated:Connect(function()
		setOpen(not isOpen)
	end)

	panel = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(820, 440), BackgroundTransparency = 0.05, Visible = false }, screen)
	UI.CenterBelowTopbar(panel)
	UI.Corner(16, panel)
	levelLabel = UI.Label({ Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(200, 36), Text = "LEVEL 1", TextXAlignment = Enum.TextXAlignment.Left }, panel)
	xpBar = UI.Bar({ Position = UDim2.fromOffset(24, 54), Size = UDim2.fromOffset(300, 10) }, UI.Accent, panel)
	xpLabel = UI.Label({ Position = UDim2.fromOffset(24, 66), Size = UDim2.fromOffset(300, 16), Text = "", TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 12 }, panel)
	streakLabel = UI.Label({ Position = UDim2.fromOffset(340, 22), Size = UDim2.fromOffset(200, 24), Text = "", TextColor3 = UI.Warn, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	local close = UI.New("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color3.fromRGB(80, 50, 50),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 16,
		TextColor3 = UI.White,
		Text = "X",
	}, panel) :: TextButton
	UI.Corner(8, close)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	UI.Label({ Position = UDim2.fromOffset(24, 92), Size = UDim2.fromOffset(200, 20), Text = "QUESTS", TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	questList = UI.Frame({ Position = UDim2.fromOffset(24, 116), Size = UDim2.fromOffset(400, 250), BackgroundTransparency = 1 }, panel)
	UI.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, questList)
	questFooter = UI.Label({ Position = UDim2.fromOffset(24, 368), Size = UDim2.fromOffset(400, 16), Text = "", TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 12 }, panel)

	UI.Label({ Position = UDim2.fromOffset(450, 92), Size = UDim2.fromOffset(200, 20), Text = "LEADERBOARDS", TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	boardsFrame = UI.Frame({ Position = UDim2.fromOffset(450, 116), Size = UDim2.fromOffset(346, 400), BackgroundTransparency = 1 }, panel)
	local slots: { { name: string, x: number, y: number } } = {
		{ name = "Weekly", x = 0, y = 0 },
		{ name = "Friends", x = 176, y = 0 },
		{ name = "BestTip", x = 0, y = 106 },
		{ name = "Knockouts", x = 176, y = 106 },
		{ name = "Arcade", x = 0, y = 212 },
	}
	for _, slot in slots do
		UI.Frame({ Name = slot.name, Position = UDim2.fromOffset(slot.x, slot.y), Size = UDim2.fromOffset(170, 104), BackgroundTransparency = 1 }, boardsFrame)
	end
	UI.Label({ Name = "TrailNote", Position = UDim2.fromOffset(176, 232), Size = UDim2.fromOffset(170, 40), Text = string.format("Top %d this week earn the gold trail.", Config.Leaderboards.WeeklyTrailTop), TextColor3 = UI.Muted, Font = UI.FontMedium, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = false, TextSize = 12, TextWrapped = true }, boardsFrame)
end

-- Parked: between rounds, or not driving at all (on foot, in the depot).
local function onRound(payload: Types.RoundStatePayload)
	local parked = (payload.phase ~= "Playing" and payload.phase ~= "Countdown") or (State.sessionState ~= "Driver" and State.sessionState ~= "")
	openButton.Visible = parked
	if not parked and isOpen then
		setOpen(false)
	end
end

function ProgressController.Init()
	requestBoards = Remotes.Get("RequestLeaderboards")
	build()
	State.ProfileChanged:Connect(function()
		if isOpen then
			render()
		end
	end)
	State.QuestsChanged:Connect(function()
		if isOpen then
			render()
		end
	end)
	State.BoardsChanged:Connect(function()
		if isOpen then
			render()
		end
	end)
	State.RoundChanged:Connect(onRound)
	State.SessionChanged:Connect(function()
		local round = State.round
		if round then
			onRound(round)
		end
	end)
end

function ProgressController.Start() end

return ProgressController
