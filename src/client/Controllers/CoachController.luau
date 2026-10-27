--!strict
-- First-match coach: one short prompt at a time in a small pill under the timer (never over the road), in order: pick
-- up, deliver, drift, boost, use an item. Each goes when done (or when its time is up); once all have gone the server
-- marks the account (CoachDone) and the coach never shows again. Words follow the input in use. Config.Coach.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.Parent.UI)

local CoachController = {}

local pill: Frame
local label: TextLabel
local step = 1 -- index into Config.Coach.Steps
local shownFor = 0 -- seconds the current step has been on screen
local progress = 0 -- seconds of drifting / boosting toward the current step
local finished = false
local sent = false

local function inputKind(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Keyboard"
end

local function advance()
	step += 1
	shownFor = 0
	progress = 0
	if step > #Config.Coach.Steps then
		finished = true
		pill.Visible = false
		if not sent then
			sent = true
			Remotes.Get("CoachDone"):FireServer()
		end
	end
end

-- Should the current step show right now (its moment has come)?
local function wants(id: string): boolean
	if id == "pickup" then
		return State.fare == nil
	elseif id == "deliver" then
		return State.fare ~= nil
	elseif id == "boost" then
		return State.boostTank >= Config.Coach.BoostTankToShow
	elseif id == "item" then
		return State.item ~= ""
	end
	return true
end

local function update(dt: number)
	local profile = State.profile
	if finished or not profile or profile.coachDone or State.GetPhase() ~= "Playing" then
		pill.Visible = false
		return
	end
	local def = Config.Coach.Steps[step]
	if not wants(def.Id) then
		pill.Visible = false
		return
	end
	local kind = inputKind()
	label.Text = if kind == "Touch" then def.Touch elseif kind == "Gamepad" then def.Gamepad else def.Keyboard
	pill.Visible = true
	shownFor += dt
	if def.Id == "drift" and State.drifting then
		progress += dt
		if progress >= Config.Coach.DriftSeconds then
			advance()
			return
		end
	elseif def.Id == "boost" and State.boosting then
		progress += dt
		if progress >= Config.Coach.BoostSeconds then
			advance()
			return
		end
	end
	if def.MaxSeconds > 0 and shownFor >= def.MaxSeconds then
		advance()
	end
end

local function onFare(payload: Types.FareEventPayload)
	if finished then
		return
	end
	local id = Config.Coach.Steps[step].Id
	if (id == "pickup" and payload.kind == "Claimed") or (id == "deliver" and payload.kind == "Delivered") then
		advance()
	end
end

local function onItem(payload: Types.ItemEventPayload)
	if not finished and Config.Coach.Steps[step].Id == "item" and payload.kind == "Used" then
		advance()
	end
end

function CoachController.Init()
	local screen = UI.Screen("CrazyFareCoach", 12)
	pill = UI.Frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromOffset(400, 32), BackgroundColor3 = UI.Black, BackgroundTransparency = 0.35, Visible = false }, screen)
	UI.Corner(16, pill)
	label = UI.Label({ Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -28, 1, -8), Text = "", TextColor3 = UI.White, Font = UI.FontMedium }, pill)
	State.FareEvent:Connect(onFare)
	State.ItemEvent:Connect(onItem)
end

function CoachController.Start()
	RunService.RenderStepped:Connect(update)
end

return CoachController
