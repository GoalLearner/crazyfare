--!strict
-- The Taxi Depot (Config.Depot): people whose SessionService state is "Depot" drive their own selected car around a yard
-- beside the City between matches (or while sitting one out). No items, no passengers, no money: a drift loop, two
-- ramps, a cone slalom, and a board with this server's longest jump and best drift (ComboService.OnDepotStunt).
-- Each person gets a parking bay; a car that falls out of the yard goes back to its bay. Knocked cones stand back up.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SessionService = require(script.Parent.SessionService)
local VehicleService = require(script.Parent.VehicleService)
local ComboService = require(script.Parent.ComboService)
local DevBlockout = require(script.Parent.Parent.Studio.DevBlockout)

local DepotService = {}

type Record = { seconds: number, name: string }

local build: DevBlockout.DepotBuild
local coneHome: { [BasePart]: CFrame } = {}
local bayOf: { [Player]: number } = {}
local driftRun: { [Player]: { seconds: number, lastAt: number } } = {}
local bestJump: Record? = nil
local bestDrift: Record? = nil
local coneClock = 0

local function freeBay(): number
	local used: { [number]: boolean } = {}
	for _, bay in bayOf do
		used[bay] = true
	end
	for i = 1, #build.spawns do
		if not used[i] then
			return i
		end
	end
	return 1
end

local function bayCFrame(player: Player): CFrame
	local bay = bayOf[player] or 1
	return build.spawns[bay] * CFrame.new(0, Config.Depot.SpawnLift, 0)
end

local function recordText(label: string, record: Record?): string
	if not record then
		return string.format("%s   %s", label, Config.Depot.NoRecord)
	end
	return string.format("%s   %.1fs   %s", label, record.seconds, string.upper(record.name))
end

local function drawBoard()
	build.jumpLabel.Text = recordText(Config.Depot.JumpLabel, bestJump)
	build.driftLabel.Text = recordText(Config.Depot.DriftLabel, bestDrift)
end

local function onStunt(player: Player, kind: string, seconds: number)
	if seconds <= 0 then
		return
	end
	if kind == "Airtime" then
		local jump = bestJump
		if not jump or seconds > jump.seconds then
			bestJump = { seconds = seconds, name = player.DisplayName }
			drawBoard()
		end
	elseif kind == "Drift" then
		local now = os.clock()
		local run = driftRun[player]
		local total = seconds
		if run and now - run.lastAt <= Config.Depot.DriftGap then
			run.seconds += seconds
			run.lastAt = now
			total = run.seconds
		else
			driftRun[player] = { seconds = seconds, lastAt = now }
		end
		local drift = bestDrift
		if not drift or total > drift.seconds then
			bestDrift = { seconds = total, name = player.DisplayName }
			drawBoard()
		end
	end
end

function DepotService.Init()
	build = DevBlockout.BuildDepot()
	for _, cone in build.cones do
		coneHome[cone] = cone.CFrame
	end
	drawBoard()

	SessionService.OnStateChanged:Connect(function(player: Player, old: string, new: string)
		if new == "Depot" then
			bayOf[player] = bayOf[player] or freeBay()
			VehicleService.SpawnDepot(player, bayCFrame(player))
		elseif old == "Depot" then
			bayOf[player] = nil
			driftRun[player] = nil
		end
	end)
	ComboService.OnDepotStunt:Connect(onStunt)
	Players.PlayerRemoving:Connect(function(player: Player)
		bayOf[player] = nil
		driftRun[player] = nil
	end)
end

function DepotService.Start()
	local floorY = Config.Depot.Center.Y
	RunService.Heartbeat:Connect(function(dt: number)
		-- out of the yard (through the floor, somehow): back to your bay
		for player in bayOf do
			local entry = VehicleService.GetDepotEntry(player)
			if entry and entry.chassis.Position.Y < floorY - Config.Depot.FallDepth then
				entry.chassis.AssemblyLinearVelocity = Vector3.zero
				entry.chassis.AssemblyAngularVelocity = Vector3.zero
				entry.model:PivotTo(bayCFrame(player))
			end
		end
		coneClock += dt
		if coneClock >= Config.Depot.ConeResetSeconds then
			coneClock = 0
			for cone, home in coneHome do
				if cone.Parent and (cone.Position - home.Position).Magnitude > Config.Depot.ConeMoved then
					cone.AssemblyLinearVelocity = Vector3.zero
					cone.AssemblyAngularVelocity = Vector3.zero
					cone.CFrame = home
				end
			end
		end
	end)
end

return DepotService
