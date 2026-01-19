---@type string, Addon
local _, addon = ...
local mini = addon.Framework
local numerics = addon.Numerics
local unitUtil = addon.UnitUtil
local combatLog = addon.CombatLogParser
local db
local eventsFrame
local initialised = false

---@type { [string]: StateEntry }
local data = {}

-- 60 seconds x 60 minutes = 1 hour
local staleSeconds = 60 * 60

-- max number of seconds between beginning and ending an inference
local pendingTimeoutSeconds = 30

---@class HealthTracker
local M = {}
addon.Tracker = M

local function Now()
	return GetTimePreciseSec()
end

---Choose an interpolation strength based on how far apart the values are.
---@param currentMax number
---@param newMax number
---@return number alpha 0..1
local function GetAdaptiveSpeed(currentMax, newMax)
	-- how different are we, relative to our current value?
	local relativeError = math.abs(newMax - currentMax) / math.max(currentMax, 1)

	-- gentle smoothing when estimates are similar
	local speedWhenClose = 0.15
	-- fast movement when estimates are very different
	local speedWhenFar = 0.85
	-- 50% difference counts as very different
	local errorForMaxSpeed = 0.50

	-- scale the error into 0..1
	local scale = relativeError / errorForMaxSpeed

	scale = numerics:Clamp(scale, 0, 1)

	-- interpolate between slow and fast update speeds
	local speed = speedWhenClose + (speedWhenFar - speedWhenClose) * scale
	return speed
end

---@param guid string
---@param unit string|nil
---@return StateEntry|nil
local function Touch(guid, unit)
	local state = data[guid]

	if not state then
		state = {
			Max = nil,
			LastSeen = Now(),
			Unit = unit,
			LastPercent = nil,
			Pending = nil,
		}
		data[guid] = state
	else
		state.LastSeen = Now()
		state.Unit = unit
	end

	return state
end

---@param state StateEntry
---@param unit string
local function BindUnit(state, unit)
	if not UnitExists(unit) then
		return
	end

	state.Unit = unit
	state.LastPercent = unitUtil:GetUnitPercent(unit) or state.LastPercent
end

---@param state StateEntry
---@param newMax number
local function ApplyInferredMax(state, newMax)
	if not newMax or newMax <= 0 then
		return
	end

	if state.Max and state.Max > 0 then
		-- smooth updates to avoid big jumps from noisy samples
		local speed = GetAdaptiveSpeed(state.Max, newMax)
		state.Max = numerics:Lerp(state.Max, newMax, speed)
	else
		state.Max = newMax
	end
end

---@param state StateEntry
local function EndInference(state)
	local unit = state.Unit

	if not unit or not UnitExists(unit) then
		return
	end

	local pending = state.Pending

	if not pending then
		return
	end

	if pending.StartedAt and (Now() - pending.StartedAt) > pendingTimeoutSeconds then
		addon:DebugPrint("Pending event was too stale, ignoring.")
		state.Pending = nil
		return
	end

	local hp = UnitHealth(unit)
	local max = UnitHealthMax(unit)

	if hp == nil or max == nil or max <= 0 then
		return
	end

	local percent = hp / max
	state.LastPercent = percent

	local percentBefore = pending.PercentBefore
	local netAmount = pending.NetAmount or 0

	-- clear pending no matter what; we got our read window
	state.Pending = nil

	-- Need a baseline percent to compare against
	if percentBefore == nil then
		return
	end

	if netAmount == 0 then
		return
	end

	local percentDeltaSigned = percent - percentBefore
	local percentDelta = math.abs(percentDeltaSigned)
	local amountDelta = math.abs(netAmount)

	addon:DebugPrint("Percent before: %s, percent now: %s, net amount: %s.", percentBefore, percent, netAmount)

	if percentDelta <= 0 then
		return
	end

	local inferredMax = amountDelta / percentDelta
	ApplyInferredMax(state, inferredMax)
end

---@param state StateEntry
---@param amount number
local function BeginInference(state, amount)
	local unit = state.Unit
	if not unit or not UnitExists(unit) then
		return
	end

	local hp = UnitHealth(unit)
	local max = UnitHealthMax(unit)

	if hp == nil or max == nil or max <= 0 then
		return
	end

	local percent = hp / max

	state.LastPercent = percent

	local pending = state.Pending

	if pending then
		-- accumulate into the same window
		pending.NetAmount = (pending.NetAmount or 0) + amount
		return
	end

	state.Pending = {
		NetAmount = amount,
		StartedAt = Now(),
		PercentBefore = percent,
	}
end

local function OnUnitHealth(_, unit)
	if not unit or not UnitExists(unit) then
		return
	end

	if UnitIsUnit(unit, "player") then
		return
	end

	local guid = UnitGUID(unit)

	if not guid then
		return
	end

	local state = data[guid]

	if not state or not state.Pending then
		return
	end

	-- Keep the unit up to date
	state.Unit = unit

	EndInference(state)

	-- important: begin a new inference to capture the current hp values
	BeginInference(state, 0)
end

local function OnCombatLog()
	local _, subevent, _, _, _, _, _, dstGUID = CombatLogGetCurrentEventInfo()

	if not dstGUID then
		return
	end

	if not addon.DebugMode then
		if not unitUtil:IsPlayerGUID(dstGUID) then
			return
		end
	end

	-- ignore self events
	if dstGUID == UnitGUID("player") then
		return
	end

	local state = Touch(dstGUID)

	if not state then
		return
	end

	if not state.Unit and UnitTokenFromGUID then
		state.Unit = UnitTokenFromGUID(dstGUID)
	end

	if subevent == "SWING_DAMAGE" then
		local amount = combatLog:GetSwingDamageAmount()
		BeginInference(state, -amount)
	elseif subevent == "SPELL_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" then
		local amount = combatLog:GetSpellDamageAmount()
		BeginInference(state, -amount)
	elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
		local amount = combatLog:GetSpellHealAmount()
		BeginInference(state, amount)
	elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
		state.LastPercent = 0
		state.Pending = nil
	end
end

local function Cleanup()
	local now = Now()

	for guid, state in pairs(data) do
		if not state.LastSeen or (now - state.LastSeen) > staleSeconds then
			data[guid] = nil
		end
	end
end

---@return number|nil current
---@return number|nil max
---@return number|nil confidence
function M:GetHealth(unit)
	if not unit or not UnitExists(unit) then
		return nil, nil
	end

	if UnitIsUnit(unit, "player") then
		return nil, nil
	end

	if not addon.DebugMode then
		if unitUtil:IsUnitInMyGroup(unit) then
			-- grouped units are reliably calculated
			return UnitHealth(unit), UnitHealthMax(unit)
		end

		if not UnitIsPlayer(unit) and not unitUtil:IsPet(unit) then
			-- mobs are reliably calculated
			return UnitHealth(unit), UnitHealthMax(unit)
		end
	end

	-- Players and pets are estiamted via combat log
	local guid = UnitGUID(unit)

	if not guid then
		return nil, nil, nil
	end

	local state = Touch(guid, unit)

	if not state then
		return nil, nil, nil
	end

	-- bind this unit to the guid
	BindUnit(state, unit)

	-- start inferring if one isn't already pending
	-- so we can get the real hp values quicker
	if not state.Pending then
		BeginInference(state, 0)
	end

	if (Now() - (state.LastSeen or 0)) > staleSeconds then
		data[guid] = nil
		return nil, nil
	end

	if not state.Max or state.LastPercent == nil then
		return nil, nil
	end

	local percent = unitUtil:GetUnitPercent(state.Unit)
	local max = math.floor(state.Max)
	local current = math.floor(max * percent)

	return current, max
end

function M:Init()
	if initialised then
		return
	end

	db = mini:GetSavedVars()
	data = db.Cache or {}
	db.Cache = data

	eventsFrame = CreateFrame("Frame")
	eventsFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	eventsFrame:RegisterEvent("UNIT_HEALTH")

	eventsFrame:SetScript("OnEvent", function(_, event, arg1)
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			OnCombatLog()
		elseif event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" then
			OnUnitHealth(event, arg1)
		end
	end)

	Cleanup()

	initialised = true
end

---@class PendingEvent
---@field NetAmount number
---@field StartedAt number
---@field PercentBefore number|nil

---@class StateEntry
---@field Unit string|nil
---@field Max number|nil
---@field LastSeen number
---@field LastPercent number|nil
---@field Pending PendingEvent|nil
