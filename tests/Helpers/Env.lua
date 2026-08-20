-- Loads MiniHealthNumbers into a mocked client and gives the tests control of the two inputs
-- the health tracker actually runs on: what the unit frames report, and what the combat log says.
--
-- The addon exists because retail hides an arena enemy's real max health - UnitHealthMax comes
-- back as a scaled stand-in, so only the percentage is trustworthy. The tracker recovers the
-- real number by pairing a combat log amount with the percentage move it caused. These helpers
-- model exactly that: a unit whose reported max is a lie, and damage events that aren't.

local harness = require("AddonHarness")
local WowMock = require("WowMock")

local M = {}

---Builds a fresh client with the addon loaded and logged in.
---@return table env
function M.Build()
	-- Settings live in saved variables and survive a reload by design. Each test wants a
	-- clean slate, so clear them before the addon loads.
	_G.MiniHealthNumbersDB = nil

	local context = harness.Load("MiniHealthNumbers")

	local env = {
		Addon = context.Addon,
		Context = context,
		Time = 1000,
		-- unit token -> { Guid, Health, Max }
		Units = {},
		-- guid -> unit token, for UnitTokenFromGUID
		Tokens = {},
		-- The payload CombatLogGetCurrentEventInfo returns next.
		Payload = {},
	}

	_G.GetTimePreciseSec = function()
		return env.Time
	end

	_G.GetTime = function()
		return env.Time
	end

	_G.UnitExists = function(unit)
		return env.Units[unit] ~= nil
	end

	_G.UnitGUID = function(unit)
		local entry = env.Units[unit]
		return entry and entry.Guid or nil
	end

	_G.UnitIsUnit = function(a, b)
		return a == b
	end

	_G.UnitHealth = function(unit)
		local entry = env.Units[unit]
		return entry and entry.Health or nil
	end

	_G.UnitHealthMax = function(unit)
		local entry = env.Units[unit]
		return entry and entry.Max or nil
	end

	_G.UnitTokenFromGUID = function(guid)
		return env.Tokens[guid]
	end

	_G.CombatLogGetCurrentEventInfo = function()
		return unpack(env.Payload, 1, env.Payload.n or #env.Payload)
	end

	harness.Login(context)

	env.Tracker = context.Addon.Tracker
	env.Parser = context.Addon.CombatLogParser

	-- Controls

	---Registers a unit. `max` is what the client reports, which for an arena enemy is a
	---stand-in rather than the real pool - pass the fake one here.
	function env.AddUnit(unit, guid, health, max)
		env.Units[unit] = { Guid = guid, Health = health, Max = max }
		env.Tokens[guid] = unit
		return guid
	end

	---Moves a unit to a health percentage of whatever max the client reports for it.
	function env.SetPercent(unit, percent)
		local entry = env.Units[unit]
		entry.Health = entry.Max * percent
	end

	function env.Advance(seconds)
		env.Time = env.Time + seconds
	end

	---Fires UNIT_HEALTH for a unit, which is what closes an inference window.
	function env.FireUnitHealth(unit)
		WowMock.FireEvent("UNIT_HEALTH", unit)
	end

	---Sets the next combat log payload and fires it.
	---@param fields table the full argument list, 1-based, exactly as the client returns it
	function env.FireCombatLog(fields)
		env.Payload = fields
		WowMock.FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end

	return env
end

-- Combat log payloads
--
-- The first eleven values are the header every subevent shares. Everything after it is
-- subevent specific, and the offset it starts at is the thing worth pinning down: swing
-- damage carries its amount at 12, and anything with a spell attached carries three spell
-- fields first and its amount at 15. An off-by-one here reports a school id as a damage
-- number, which looks plausible enough on screen to go unnoticed.

---@param subevent string
---@param dstGuid string
---@return table header eleven values
local function header(subevent, dstGuid)
	return {
		1234.5, -- timestamp
		subevent,
		false, -- hideCaster
		"Player-1-Attacker",
		"Attacker",
		0, -- srcFlags
		0, -- srcRaidFlags
		dstGuid,
		"Victim",
		0, -- dstFlags
		0, -- dstRaidFlags
	}
end

---SWING_DAMAGE: amount, overkill, school, resisted, blocked, absorbed from index 12.
function M.SwingDamage(dstGuid, amount, overkill, resisted, blocked, absorbed)
	local fields = header("SWING_DAMAGE", dstGuid)

	fields[12] = amount
	fields[13] = overkill or -1
	fields[14] = 1 -- school
	fields[15] = resisted or -1
	fields[16] = blocked or -1
	fields[17] = absorbed or -1
	fields.n = 17

	return fields
end

---SPELL_DAMAGE: spellId, spellName, spellSchool at 12-14, then amount from index 15.
function M.SpellDamage(dstGuid, amount, overkill, resisted, blocked, absorbed, subevent)
	local fields = header(subevent or "SPELL_DAMAGE", dstGuid)

	fields[12] = 133 -- spellId
	fields[13] = "Fireball"
	fields[14] = 4 -- spellSchool
	fields[15] = amount
	fields[16] = overkill or -1
	fields[17] = 4 -- school
	fields[18] = resisted or -1
	fields[19] = blocked or -1
	fields[20] = absorbed or -1
	fields.n = 20

	return fields
end

---SPELL_HEAL: spell fields at 12-14, then amount, overhealing, absorbed.
function M.SpellHeal(dstGuid, amount, overheal, absorbed, subevent)
	local fields = header(subevent or "SPELL_HEAL", dstGuid)

	fields[12] = 2050
	fields[13] = "Heal"
	fields[14] = 2
	fields[15] = amount
	fields[16] = overheal or 0
	fields[17] = absorbed or 0
	fields.n = 17

	return fields
end

---A payload for a subevent the parser is not meant to handle.
function M.Other(dstGuid, subevent)
	local fields = header(subevent, dstGuid)
	fields.n = 11
	return fields
end

return M
