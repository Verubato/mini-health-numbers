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

function M:GetSwingDamageAmount()
	local _, subevent = CombatLogGetCurrentEventInfo()

	if subevent ~= "SWING_DAMAGE" then
		addon:DebugPrint("Expected SWING_DAMAGE but was %s.", subevent)
		return 0
	end

	local amount, overkill, _, resisted, blocked, absorbed = select(12, CombatLogGetCurrentEventInfo())
	return EffectiveDamage(amount, overkill, resisted, blocked, absorbed)
end

function M:GetSpellDamageAmount()
	local _, subevent = CombatLogGetCurrentEventInfo()

	if subevent ~= "SPELL_DAMAGE" and subevent ~= "RANGE_DAMAGE" and subevent ~= "SPELL_PERIODIC_DAMAGE" then
		addon:DebugPrint("Expected spell damage event but was %s.", subevent)
		return 0
	end

	local amount, overkill, _, resisted, blocked, absorbed = select(15, CombatLogGetCurrentEventInfo())
	return EffectiveDamage(amount, overkill, resisted, blocked, absorbed)
end

function M:GetSpellHealAmount()
	local _, subevent = CombatLogGetCurrentEventInfo()

	if subevent ~= "SPELL_HEAL" and subevent ~= "SPELL_PERIODIC_HEAL" then
		addon:DebugPrint("Expected spell heal event but was %s.", subevent)
		return 0
	end

	local amount, overheal, absorbed = select(15, CombatLogGetCurrentEventInfo())

	---@diagnostic disable-next-line: param-type-mismatch
	return math.max(0, EffectiveHeal(amount, overheal) - numerics:NonNegativeOrZero(absorbed))
end
