--!strict
-- The 7-day streak calendar (Config.Streak): when today's prize is paid (StreakEvent) a card shows the week, days
-- done ticked, today outlined, then tomorrow's prize and what a missed day costs. It waits for a quiet moment (see
-- parked) and closes itself after AutoCloseSeconds or when a race starts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Prizes = require(Shared:WaitForChild("Prizes"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local CalendarController = {}

local GAP = 8
local PAD = 20

local cfg = Config.Streak
local card: Frame
local daysLabel: TextLabel
local row: Frame
local tomorrowLabel: TextLabel
local pending: Types.StreakPayload? = nil
local shownAt = 0

-- A quiet moment: the pre-match lobby after the Starter Pack offer (which owns that moment), a pit stop (matches run
-- back to back, so it's the first calm moment for someone who joined mid-match), or not driving. Never while racing
-- or on the podium (the crate and the map vote).
local function parked(): boolean
	local state = State.sessionState
	if state == "Title" or state == "" then
		return false
	end
	local phase = State.GetPhase()
	if phase == "Waiting" then
		local profile = State.profile
		return not (profile and profile.showStarterPack)
	elseif phase == "PitStop" then
		return true
	end
	return state ~= "Driver"
end

local function render(payload: Types.StreakPayload)
	for _, child in row:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	daysLabel.Text = string.format(cfg.StreakLine, payload.days)
	for i, prize in cfg.Calendar do
		local today = i == payload.slot
		local color = Config.Drops.Colors[prize.Rarity] or UI.Accent
		local tile = UI.Frame({
			Size = UDim2.fromOffset(cfg.TileWidth, cfg.TileHeight),
			LayoutOrder = i,
			BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), if today then 0.35 else 0.6),
			BackgroundTransparency = if i > payload.slot then 0.45 else 0.05,
		}, row)
		UI.Corner(10, tile)
		if today then
			UI.Stroke(UI.Warn, 3, tile).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		end
		UI.Label({ Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 16), Text = if today then cfg.TodayLabel else string.format(cfg.DayLabel, i), TextColor3 = if today then UI.Warn else UI.Muted, Font = UI.FontMedium, TextScaled = false, TextSize = 12 }, tile)
		local text = if today and payload.duplicateGems then string.format(cfg.DuplicateLabel, payload.duplicateGems) else Prizes.Short(prize)
		UI.Label({ Position = UDim2.fromOffset(6, 26), Size = UDim2.new(1, -12, 0, 44), Text = text, TextWrapped = true, TextScaled = false, TextSize = 14, TextColor3 = if i > payload.slot then UI.Muted else UI.White }, tile)
		if i <= payload.slot then
			UI.Label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 20), Text = "\u{2713}", TextColor3 = UI.Cash, TextScaled = false, TextSize = 18 }, tile)
		end
	end
	local nextSlot = payload.slot % #cfg.Calendar + 1
	tomorrowLabel.Text = string.format(cfg.TomorrowLine, payload.days + 1, Prizes.Name(cfg.Calendar[nextSlot]))
end

local function close()
	card.Visible = false
end

local function tryShow()
	local payload = pending
	if not payload or not parked() then
		return
	end
	pending = nil
	render(payload)
	card.Visible = true
	local at = os.clock()
	shownAt = at
	task.delay(cfg.AutoCloseSeconds, function()
		if shownAt == at then
			close()
		end
	end)
end

local function build()
	local screen = UI.Screen("CrazyFareCalendar", 23)
	local count = #cfg.Calendar
	local rowWidth = count * cfg.TileWidth + (count - 1) * GAP
	card = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(rowWidth + PAD * 2, cfg.TileHeight + 172), BackgroundTransparency = 0.05, Visible = false }, screen)
	UI.CenterBelowTopbar(card)
	UI.Corner(16, card)
	UI.Label({ Position = UDim2.fromOffset(PAD, 12), Size = UDim2.fromOffset(300, 32), Text = cfg.Title, TextColor3 = UI.Accent, TextXAlignment = Enum.TextXAlignment.Left }, card)
	daysLabel = UI.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -PAD, 0, 12), Size = UDim2.fromOffset(160, 32), Text = "", TextColor3 = UI.Warn, TextXAlignment = Enum.TextXAlignment.Right }, card)
	row = UI.Frame({ Position = UDim2.fromOffset(PAD, 56), Size = UDim2.fromOffset(rowWidth, cfg.TileHeight), BackgroundTransparency = 1 }, card)
	UI.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local footerY = 56 + cfg.TileHeight + 12
	tomorrowLabel = UI.Label({ Position = UDim2.fromOffset(PAD, footerY), Size = UDim2.new(1, -PAD * 2, 0, 20), Text = "", TextColor3 = UI.White, Font = UI.FontMedium, TextScaled = false, TextSize = 15 }, card)
	UI.Label({ Position = UDim2.fromOffset(PAD, footerY + 22), Size = UDim2.new(1, -PAD * 2, 0, 20), Text = cfg.LoseLine, TextColor3 = UI.Danger, Font = UI.FontMedium, TextScaled = false, TextSize = 15 }, card)
	local button = UI.New("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(160, 40),
		BackgroundColor3 = Color3.fromRGB(60, 140, 80),
		BorderSizePixel = 0,
		Font = UI.Font,
		TextSize = 18,
		TextColor3 = UI.White,
		Text = cfg.Button,
	}, card) :: TextButton
	UI.Corner(10, button)
	button.Activated:Connect(close)
end

function CalendarController.Init()
	build()
	Remotes.Get("StreakEvent").OnClientEvent:Connect(function(payload: Types.StreakPayload)
		pending = payload
		tryShow()
	end)
	State.RoundChanged:Connect(function()
		if card.Visible and not parked() then
			close() -- a race is starting: clear the road
		end
		tryShow()
	end)
	State.SessionChanged:Connect(tryShow)
	State.ProfileChanged:Connect(tryShow) -- the Starter Pack offer was closed
end

function CalendarController.Start() end

return CalendarController
