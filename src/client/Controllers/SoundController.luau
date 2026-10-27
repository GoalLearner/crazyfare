--!strict
-- Every sound in the game, keyed by Config.Sounds.Ids. An id of 0 means "no asset yet" and plays nothing, so the
-- hooks are wired now and come alive the moment the owner pastes asset ids into Config.

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local State = require(script.Parent.Parent.State)

local SoundController = {}

local sounds: { [string]: Sound } = {}
local engine: Sound? = nil
local drift: Sound? = nil
local music: Sound? = nil
local lastPhase = ""

local function make(name: string, id: number, looped: boolean, volume: number): Sound?
	if id <= 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Looped = looped
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local function play(name: string)
	local sound = sounds[name]
	if sound then
		sound:Play()
	end
end

-- One coin per paid stunt, each its own copy so fast stunts overlap; pitch climbs with the chain.
local function playCoin(chain: number)
	local coin = sounds.Coin
	if not coin then
		return
	end
	local sound = coin:Clone()
	sound.PlaybackSpeed = 1 + math.max(0, chain - 1) * Config.Stunts.CoinPitchPerChain
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

local function onFare(payload: Types.FareEventPayload)
	if payload.kind == "Stunt" then
		if (payload.amount or 0) > 0 then
			playCoin(payload.chain or 1)
		end
	elseif payload.kind == "Claimed" then
		play("Pickup")
		play("Board")
	elseif payload.kind == "Delivered" then
		play("Deliver")
		play("Thanks")
	elseif payload.kind == "Bailed" then
		play("Bail")
		play("Angry")
	elseif payload.kind == "Hurt" and payload.source == "crash" then
		play("Crash")
	end
end

local function onItem(payload: Types.ItemEventPayload)
	if payload.kind == "Splat" then
		play("Splat")
	elseif payload.kind == "Spinout" then
		play("Spinout")
	elseif payload.kind == "Boost" then
		play("Boost")
	end
end

local function onRound(payload: Types.RoundStatePayload)
	if payload.phase == lastPhase then
		return
	end
	lastPhase = payload.phase
	if payload.phase == "Countdown" then
		play("Countdown")
	elseif payload.phase == "Playing" then
		play("Go")
	elseif payload.phase == "RoundEnd" or payload.phase == "MatchEnd" then
		play("RoundEnd")
	end
end

local function onHonk()
	local profile = State.profile
	if profile and profile.vip and sounds.HonkVip then
		play("HonkVip")
	else
		play("Honk")
	end
end

function SoundController.Init()
	local ids = Config.Sounds.Ids
	local volume = Config.Sounds.Volume
	for name, id in ids do
		if name ~= "Engine" and name ~= "Drift" and name ~= "Music" then
			local sound = make(name, id, false, volume)
			if sound then
				sounds[name] = sound
			end
		end
	end
	for name, id in Config.Sounds.PassengerLines do
		local sound = make("Voice" .. name, id, false, volume)
		if sound then
			sounds[name] = sound
		end
	end
	engine = make("Engine", ids.Engine, true, volume * 0.6)
	drift = make("Drift", ids.Drift, true, volume * 0.8)
	music = make("Music", ids.Music, true, Config.Sounds.MusicVolume)
	if music then
		music:Play()
	end

	State.FareEvent:Connect(onFare)
	State.ItemEvent:Connect(onItem)
	State.RoundChanged:Connect(onRound)
	State.Honk:Connect(onHonk)
end

function SoundController.Start()
	RunService.Heartbeat:Connect(function()
		local eng = engine
		if eng then
			local frac = math.clamp(State.speed / State.stats.TopSpeed, 0, 1.2)
			eng.PlaybackSpeed = 0.7 + frac * 0.8
			if State.chassis and not eng.IsPlaying then
				eng:Play()
			end
		end
		local dr = drift
		if dr then
			if State.drifting and not dr.IsPlaying then
				dr:Play()
			elseif not State.drifting and dr.IsPlaying then
				dr:Stop()
			end
		end
	end)
end

return SoundController
