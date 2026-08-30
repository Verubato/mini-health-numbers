-- Loads the whole addon into a mocked client and drives it through login.
-- The shared body lives in build/Lua/SmokeTest.lua.

local fw = require("TestFramework")
local smoke = require("SmokeTest")
local WowMock = require("WowMock")

---The header's subtitle is built by the framework and never handed back to the addon, so a
---test finds it the way a player reads it, by its words.
---@param text string
---@return boolean
local function HasText(text)
	for _, frame in ipairs(WowMock.Frames) do
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.GetText and region:GetText() == text then
				return true
			end
		end
	end

	return false
end

smoke.Run("MiniHealthNumbers", {
	extra = function(context)
		fw.eq(context.Addon.Framework.CustomStyling, true, "custom styling on")
		fw.eq(context.Addon.Framework.CustomStylingOverrides.Button, false, "stock buttons")
		fw.truthy(HasText("Shows real NPC/player HP."), "the subtitle under the panel title")
	end,
})
