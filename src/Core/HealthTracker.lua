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
			LastPercentAt = nil,
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
local function ObserveHealth(state)
	local unit = state.Unit

	if not unit or not UnitExists(unit) then
		return
	end

	local percent = unitUtil:UnitHealthPercent(unit)

	if percent == nil then
		return
	end

	state.LastPercent = percent
	state.LastPercentAt = Now()
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
local function TryEndInference(state)
	local pending = state.Pending

	if not pending or not pending.StartPercent or state.LastPercent == nil then
		return false
	end

	-- if we timed out, discard
	if (Now() - (pending.StartedAt or 0)) > pendingTimeoutSeconds then
		state.Pending = nil
		return false
	end

	local before = pending.StartPercent
	local after = state.LastPercent
	local netAmount = pending.NetAmount or 0
	local percentDelta = math.abs(after - before)

	if state.Unit then
		addon:DebugPrint(
			"%s: percent before: %s, percent now: %s, net amount: %s.",
			UnitName(state.Unit),
			before,
			after,
			netAmount
		)
	end

	if percentDelta <= 0 or netAmount == 0 then
		return false
	end

	local inferredMax = math.abs(netAmount) / percentDelta
	ApplyInferredMax(state, inferredMax)

	state.Pending = nil
	return true
end

---@param state StateEntry
---@param netAmount number
local function ContinueInference(state, netAmount)
	local pending = state.Pending

	if not pending then
		state.Pending = {
			NetAmount = netAmount,
			StartedAt = Now(),
			StartPercent = state.LastPercent,
		}

		return
	end

	if pending.StartedAt and (Now() - pending.StartedAt) > pendingTimeoutSeconds then
		-- window is too old, start a new one
		state.Pending = {
			NetAmount = netAmount,
			StartedAt = Now(),
			StartPercent = state.LastPercent,
		}
	else
		-- accumulate into the same window
		pending.NetAmount = (pending.NetAmount or 0) + netAmount
	end
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

	local state = Touch(guid, unit)

	if not state then
		return
	end

	-- Only proceed if health changed
	local newPercent = unitUtil:UnitHealthPercent(unit)

	if newPercent == nil or newPercent == state.LastPercent then
		return
	end

	addon:DebugPrint("Health event for %s, pending %s.", unit, state.Pending and state.Pending.NetAmount or 0)

	-- refresh their new hp values
	ObserveHealth(state)

	-- If this is the first health observation after we started a pending window
	-- backfill the starting value to ensure a valid starting point
	if state.Pending and state.Pending.StartPercent == nil then
		state.Pending.StartPercent = state.LastPercent
	end

	if state.Pending then
		TryEndInference(state)
	end
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

	if not state.Unit then
		-- can't map to a unit, so we can't do anything with this data
		return
	end

	local netAmount = nil

	if subevent == "SWING_DAMAGE" then
		netAmount = -combatLog:GetSwingDamageAmount()
	elseif subevent == "SPELL_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" then
		netAmount = -combatLog:GetSpellDamageAmount()
	elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
		netAmount = combatLog:GetSpellHealAmount()
	elseif subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
		state.LastPercent = 0
		state.LastPercentAt = Now()
		state.Pending = nil
	end

	if netAmount and math.abs(netAmount) > 0 then
		addon:DebugPrint("%s: %s damage/heal.", state.Unit, tostring(netAmount))

		-- update the pending amounts
		ContinueInference(state, netAmount)

		state.LastSeen = Now()
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
		return UnitHealth("player"), UnitHealthMax("player")
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

	-- capture the current hp values
	ObserveHealth(state)

	if (Now() - (state.LastSeen or 0)) > staleSeconds then
		data[guid] = nil
		return nil, nil
	end

	if not state.Max or state.LastPercent == nil then
		return nil, nil
	end

	local percent = unitUtil:UnitHealthPercent(state.Unit)
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
		elseif event == "UNIT_HEALTH" then
			OnUnitHealth(event, arg1)
		end
	end)

	Cleanup()

	initialised = true
end

---@class PendingEvent
---@field NetAmount number
---@field StartedAt number
---@field StartPercent number|nil

---@class StateEntry
---@field Unit string|nil
---@field Max number|nil
---@field LastSeen number
---@field LastPercent number|nil
---@field LastPercentAt number|nil
---@field Pending PendingEvent|nil
