local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
local M = {}

addon.Config = M

function M:Init()
	local verticalSpacing = mini.VerticalSpacing
	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -16)
	title:SetText(addonName)

	local lines = mini:TextBlock({
		Parent = panel,
		Lines = {
			"Important notes:",
			"  - Mobs health is perfectly determined.",
			"  - Health of players in your group is perfectly determined.",
			"  - Everyone else (enemy players, non-grouped players) are guestimated based on combat log events.",
		},
	})

	lines:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -verticalSpacing)

	SLASH_MINITEMPLATE1 = "/minitemplate"
	SLASH_MINITEMPLATE2 = "/minit"

	mini:RegisterSlashCommand(category, panel)
end
