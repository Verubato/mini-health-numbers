---@type string, Addon
local _, addon = ...
local numerics = addon.Numerics

---@class CombatLogParser
local M = {}
addon.CombatLogParser = M

local function EffectiveDamage(amount, overkill, resisted, blocked, absorbed)
	amount = numerics:ToNumberOrZero(amount)

	-- combat log uses -1 values for not applicable
	overkill = numerics:NonNegativeOrZero(overkill)
	resisted = numerics:NonNegativeOrZero(resisted)
	blocked = numerics:NonNegativeOrZero(blocked)
	absorbed = numerics:NonNegativeOrZero(absorbed)

	local effective = amount - overkill - resisted - blocked - absorbed
	return math.max(0, effective)
end

local function EffectiveHeal(amount, overheal)
	amount = numerics:ToNumberOrZero(amount)
	overheal = numerics:NonNegativeOrZero(overheal)

	local effective = amount - overheal
	return math.max(0, effective)
end

local function ReadSwingDamage(...)
	local subevent = select(2, ...)

	if subevent ~= "SWING_DAMAGE" then
		addon:DebugPrint("Expected SWING_DAMAGE but was %s.", subevent)
		return 0
	end

	local amount, overkill, _, resisted, blocked, absorbed = select(12, ...)
	return EffectiveDamage(amount, overkill, resisted, blocked, absorbed)
end

local function ReadSpellDamage(...)
	local subevent = select(2, ...)

	if subevent ~= "SPELL_DAMAGE" and subevent ~= "RANGE_DAMAGE" and subevent ~= "SPELL_PERIODIC_DAMAGE" then
		addon:DebugPrint("Expected spell damage event but was %s.", subevent)
		return 0
	end

	local amount, overkill, _, resisted, blocked, absorbed = select(15, ...)
	return EffectiveDamage(amount, overkill, resisted, blocked, absorbed)
end

local function ReadSpellHeal(...)
	local subevent = select(2, ...)

	if subevent ~= "SPELL_HEAL" and subevent ~= "SPELL_PERIODIC_HEAL" then
		addon:DebugPrint("Expected spell heal event but was %s.", subevent)
		return 0
	end

	local amount, overheal, absorbed = select(15, ...)

	---@diagnostic disable-next-line: param-type-mismatch
	return math.max(0, EffectiveHeal(amount, overheal) - numerics:NonNegativeOrZero(absorbed))
end

-- Each getter takes the combat log payload as varargs. Reading the current event is a call into
-- the client and one damage event asks three of these questions, so the caller reads it once and
-- passes it down. Called with nothing, they read it themselves: the read is not routed back
-- through the public method, so a client with no current event answers 0 rather than looping.

---@param ... any the CLEU payload
function M:GetSwingDamageAmount(...)
	if select("#", ...) > 0 then
		return ReadSwingDamage(...)
	end

	return ReadSwingDamage(CombatLogGetCurrentEventInfo())
end

---@param ... any the CLEU payload
function M:GetSpellDamageAmount(...)
	if select("#", ...) > 0 then
		return ReadSpellDamage(...)
	end

	return ReadSpellDamage(CombatLogGetCurrentEventInfo())
end

---@param ... any the CLEU payload
function M:GetSpellHealAmount(...)
	if select("#", ...) > 0 then
		return ReadSpellHeal(...)
	end

	return ReadSpellHeal(CombatLogGetCurrentEventInfo())
end
