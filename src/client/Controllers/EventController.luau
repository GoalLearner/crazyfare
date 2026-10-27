--!strict
-- The live-event line under the Gems (Config.Events): "GOLDEN HOUR  42:10 LEFT" while one runs, and between matches
-- the next one in the player's own time ("DOUBLE GEMS  SUN 10:00 AM") when it starts within SoonHours.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Events = require(Shared:WaitForChild("Events"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local EventController = {}

local label: TextLabel
local nextUpdate = 0

local function between(): boolean
	local phase = State.GetPhase()
	return phase == "Waiting" or phase == "PreCountdown" or phase == "MatchEnd" or phase == "RoundEnd" or phase == "PitStop"
end

local function update()
	local t = workspace:GetServerTimeNow()
	local cfg = Config.Events
	local text = ""
	local color = UI.White
	local kind, endsAt = Events.Live(t)
	local live = if kind then cfg.Kinds[kind] else nil
	if live then
		text = string.format(cfg.LiveLine, live.Name, UI.FormatTime(endsAt - t))
		color = live.Color
	elseif between() then
		local nextKind, startsAt = Events.Next(t)
		local soon = if nextKind then cfg.Kinds[nextKind] else nil
		if soon and startsAt - t <= cfg.SoonHours * 3600 then
			local when = DateTime.fromUnixTimestamp(math.floor(startsAt)):FormatLocalTime("ddd h:mm A", "en-us")
			text = string.format(cfg.SoonLine, soon.Name, string.upper(when))
			color = soon.Color
		end
	end
	label.Text = text
	label.TextColor3 = color
	label.Visible = text ~= ""
end

function EventController.Init()
	local screen = UI.Screen("CrazyFareEvent", 10)
	label = UI.Label({
		Position = UDim2.fromOffset(24, Config.Hud.EventChipY),
		Size = UDim2.fromOffset(260, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = UI.FontMedium,
		TextStrokeTransparency = 0.4,
		Text = "",
		Visible = false,
	}, screen)
	UI.OnFit(function()
		label.Position = UDim2.fromOffset(24, UI.BelowTopbar(Config.Hud.EventChipY))
	end)
end

function EventController.Start()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextUpdate then
			return
		end
		nextUpdate = now + 0.5
		update()
	end)
end

return EventController
