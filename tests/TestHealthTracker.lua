-- The health tracker is the reason this addon exists. Retail will not tell you an arena
-- enemy's real max health - UnitHealthMax reports a scaled stand-in - so the tracker recovers
-- it by pairing a combat log amount against the percentage move that amount caused:
--
--     max = |damage| / |percent before - percent after|
--
-- Everything that makes that hard is what these tests cover: several hits landing before the
-- health event arrives, a window going stale, a first estimate being refined by a second, and
-- all the states where guessing would be worse than reporting nothing.

local fw = require("TestFramework")
local Env = require("Env")

local VICTIM = "Player-1-Victim"

fw.describe("MiniHealthNumbers - max health inference", function()
	local env

	fw.before_each(function()
		env = Env.Build()
		-- An arena enemy: the client reports a max of 100, which is a stand-in. The real
		-- pool is whatever the tests below make the damage and percentages imply.
		env.AddUnit("arena1", VICTIM, 100, 100)

		-- One health event at full health, before any damage. The tracker needs a percentage
		-- to measure from, and the first observation only establishes that baseline - a
		-- window opened before it is deliberately thrown away, because the damage that
		-- opened it happened at an unknown starting percentage.
		env.FireUnitHealth("arena1")
	end)

	fw.it("infers max health from one hit and the percentage it moved", function()
		-- 500 damage took them from 100% to 50%, so the real pool is 1000.
		env.FireCombatLog(Env.SwingDamage(VICTIM, 500))
		env.SetPercent("arena1", 0.5)
		env.FireUnitHealth("arena1")

		local current, max = env.Tracker:GetHealthByGuid(VICTIM)

		fw.eq(max, 1000, "inferred max")
		fw.eq(current, 500, "current health at 50%")
	end)

	fw.it("accumulates several hits that land before the health event", function()
		-- Health events are throttled, so a burst arrives as one percentage move. The window
		-- has to sum the amounts rather than infer from whichever hit happened to be last.
		env.FireCombatLog(Env.SwingDamage(VICTIM, 200))
		env.FireCombatLog(Env.SpellDamage(VICTIM, 300))
		env.FireCombatLog(Env.SwingDamage(VICTIM, 500))

		env.SetPercent("arena1", 0.5)
		env.FireUnitHealth("arena1")

		local _, max = env.Tracker:GetHealthByGuid(VICTIM)

		fw.eq(max, 2000, "1000 total damage over 50% implies a 2000 pool")
	end)

	fw.it("nets a heal against the damage in the same window", function()
		env.FireCombatLog(Env.SwingDamage(VICTIM, 800))
		env.FireCombatLog(Env.SpellHeal(VICTIM, 300))

		env.SetPercent("arena1", 0.5)
		env.FireUnitHealth("arena1")

		local _, max = env.Tracker:GetHealthByGuid(VICTIM)

		fw.eq(max, 1000, "net 500 over 50% implies a 1000 pool")
	end)

	fw.it("refines an existing estimate rather than replacing it outright", function()
		env.FireCombatLog(Env.SwingDamage(VICTIM, 500))
		env.SetPercent("arena1", 0.5)
		env.FireUnitHealth("arena1")

		local _, first = env.Tracker:GetHealthByGuid(VICTIM)
		fw.eq(first, 1000, "first estimate")

		-- A second sample implying 1100. A noisy sample should nudge the estimate, not
		-- become it, so the result lands strictly between the two.
		env.Advance(1)
		env.FireCombatLog(Env.SwingDamage(VICTIM, 275))
		env.SetPercent("arena1", 0.25)
		env.FireUnitHealth("arena1")

		local _, second = env.Tracker:GetHealthByGuid(VICTIM)

		fw.truthy(second > 1000, "estimate moved toward the new sample, got " .. tostring(second))
		fw.truthy(second < 1100, "estimate did not jump straight to it, got " .. tostring(second))
	end)

	fw.it("discards a window that went stale before any health event arrived", function()
		env.FireCombatLog(Env.SwingDamage(VICTIM, 500))

		-- Nothing closed the window and it has aged out (the tracker allows 30 seconds).
		-- Pairing this damage with a much later percentage move would infer a wildly
		-- wrong pool.
		env.Advance(31)
		env.SetPercent("arena1", 0.5)
		env.FireUnitHealth("arena1")

		local _, max = env.Tracker:GetHealthByGuid(VICTIM)

		fw.is_nil(max, "no estimate from a stale window")
	end)

	fw.it("reports nothing until it has seen enough to infer from", function()
		local current, max = env.Tracker:GetHealthByGuid(VICTIM)

		fw.is_nil(max, "max before any damage")
		fw.is_nil(current, "current before any damage")
	end)

	fw.it("ignores damage dealt to a non-player target", function()
		-- Totems, pets and training dummies all take damage; only players are tracked.
		env.AddUnit("target", "Creature-0-1-2-3-4-5", 100, 100)

		env.FireCombatLog(Env.SwingDamage("Creature-0-1-2-3-4-5", 500))
		env.SetPercent("target", 0.5)
		env.FireUnitHealth("target")

		local _, max = env.Tracker:GetHealthByGuid("Creature-0-1-2-3-4-5")

		fw.is_nil(max, "creatures are not tracked")
	end)

	fw.it("does not infer from a hit that moved no percentage", function()
		-- A hit fully absorbed by a shield: real damage in the log, no health movement.
		env.FireCombatLog(Env.SwingDamage(VICTIM, 500, -1, -1, -1, 500))
		env.FireUnitHealth("arena1")

		local _, max = env.Tracker:GetHealthByGuid(VICTIM)

		fw.is_nil(max, "no estimate without a percentage move")
	end)

	fw.it("returns the player's real values straight from the client", function()
		-- The player's own max health is never hidden, so the inference path is skipped.
		env.AddUnit("player", "Player-1-Me", 4321, 8642)

		local current, max = env.Tracker:GetHealth("player")

		fw.eq(current, 4321, "player current")
		fw.eq(max, 8642, "player max")
	end)

	fw.it("reports nothing for a unit that does not exist", function()
		local current, max = env.Tracker:GetHealth("arena5")

		fw.is_nil(max, "max for a missing unit")
		fw.is_nil(current, "current for a missing unit")
	end)
end)
