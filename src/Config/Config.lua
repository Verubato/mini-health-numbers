---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework

---@class Config
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

	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 0, -verticalSpacing)
	title:SetText(string.format("%s - %s", addonName, version))

	local lines = mini:TextBlock({
		Parent = panel,
		Lines = {
			"Note:",
			"  - Mob health is determined with full accuracy.",
			"  - Players in your group are determined with full accuracy.",
			"  - Everyone else (enemy players and non-grouped players) are estimated based on combat log events.",
		},
	})

	lines:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -verticalSpacing)

	mini:RegisterSlashCommand(category, panel, {
		"/minihealthnumbers",
		"/minihn",
		"/mhn",
	})
end
