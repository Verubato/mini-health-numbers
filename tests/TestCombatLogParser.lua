-- The combat log parser turns a raw CLEU payload into the amount of health that actually
-- moved. Two things make it worth pinning down:
--
--   * The field offsets. Swing damage carries its amount at index 12; anything with a spell
--     attached carries three spell fields first and its amount at 15. Read the wrong one and
--     a spell school id becomes a damage number - a small, plausible-looking value that the
--     health tracker will happily infer a max health from.
--   * The -1 sentinels. The combat log uses -1 rather than nil for "not applicable", so a
--     naive subtraction adds health instead of removing it.

local fw = require("TestFramework")
local Env = require("Env")

fw.describe("MiniHealthNumbers - combat log parser", function()
	local env

	fw.before_each(function()
		env = Env.Build()
	end)

	-- Offsets

	fw.it("reads a swing amount from index 12", function()
		env.Payload = Env.SwingDamage("Player-1-Victim", 500)

		fw.eq(env.Parser:GetSwingDamageAmount(), 500, "swing amount")
	end)

	fw.it("reads a spell amount from index 15, past the three spell fields", function()
		env.Payload = Env.SpellDamage("Player-1-Victim", 700)

		fw.eq(env.Parser:GetSpellDamageAmount(), 700, "spell amount")
	end)

	fw.it("reads a heal amount from index 15", function()
		env.Payload = Env.SpellHeal("Player-1-Victim", 300)

		fw.eq(env.Parser:GetSpellHealAmount(), 300, "heal amount")
	end)

	-- Sentinels
	--
	-- Every mitigation field arrives as -1 when it doesn't apply. Subtracting that would
	-- report more damage than was dealt.

	fw.it("treats the -1 sentinels as nothing mitigated", function()
		env.Payload = Env.SwingDamage("Player-1-Victim", 500, -1, -1, -1, -1)

		fw.eq(env.Parser:GetSwingDamageAmount(), 500, "swing with sentinels")

		env.Payload = Env.SpellDamage("Player-1-Victim", 500, -1, -1, -1, -1)

		fw.eq(env.Parser:GetSpellDamageAmount(), 500, "spell with sentinels")
	end)

	fw.it("subtracts each mitigation field that did apply", function()
		-- 1000 swung, 100 overkilled, 200 resisted, 50 blocked, 150 absorbed.
		env.Payload = Env.SwingDamage("Player-1-Victim", 1000, 100, 200, 50, 150)

		fw.eq(env.Parser:GetSwingDamageAmount(), 500, "swing after mitigation")
	end)

	fw.it("subtracts overhealing and absorbs from a heal", function()
		env.Payload = Env.SpellHeal("Player-1-Victim", 1000, 400, 100)

		fw.eq(env.Parser:GetSpellHealAmount(), 500, "heal after overheal and absorb")
	end)

	fw.it("never reports a negative amount", function()
		-- A hit entirely absorbed still moved no health, and a negative would be read as a
		-- heal by the tracker.
		env.Payload = Env.SwingDamage("Player-1-Victim", 300, -1, -1, -1, 300)

		fw.eq(env.Parser:GetSwingDamageAmount(), 0, "fully absorbed swing")

		env.Payload = Env.SpellHeal("Player-1-Victim", 300, 300, 0)

		fw.eq(env.Parser:GetSpellHealAmount(), 0, "fully overhealed heal")
	end)

	fw.it("handles a non-numeric amount as zero", function()
		env.Payload = Env.SwingDamage("Player-1-Victim", nil)

		fw.eq(env.Parser:GetSwingDamageAmount(), 0, "nil amount")
	end)

	-- Subevent guards

	fw.it("returns zero when asked to read the wrong subevent", function()
		env.Payload = Env.SpellDamage("Player-1-Victim", 700)
		fw.eq(env.Parser:GetSwingDamageAmount(), 0, "spell payload read as a swing")

		env.Payload = Env.SwingDamage("Player-1-Victim", 500)
		fw.eq(env.Parser:GetSpellDamageAmount(), 0, "swing payload read as a spell")

		env.Payload = Env.SpellDamage("Player-1-Victim", 700)
		fw.eq(env.Parser:GetSpellHealAmount(), 0, "damage payload read as a heal")
	end)

	fw.it("accepts every damage subevent that shares the spell layout", function()
		for _, subevent in ipairs({ "SPELL_DAMAGE", "RANGE_DAMAGE", "SPELL_PERIODIC_DAMAGE" }) do
			env.Payload = Env.SpellDamage("Player-1-Victim", 250, nil, nil, nil, nil, subevent)

			fw.eq(env.Parser:GetSpellDamageAmount(), 250, subevent)
		end
	end)

	fw.it("accepts both heal subevents", function()
		for _, subevent in ipairs({ "SPELL_HEAL", "SPELL_PERIODIC_HEAL" }) do
			env.Payload = Env.SpellHeal("Player-1-Victim", 250, 0, 0, subevent)

			fw.eq(env.Parser:GetSpellHealAmount(), 250, subevent)
		end
	end)
end)
