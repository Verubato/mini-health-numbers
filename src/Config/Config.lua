---@type string, Addon
local addonName, addon = ...
local mini = addon.Framework

---@class Config
local M = {}

---@class Db
local dbDefaults = {
	ExcludeMax = false,
}

---@type Db
local db

addon.Config = M

function M:Init()
	local verticalSpacing = mini.VerticalSpacing
	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	db = mini:GetSavedVars(dbDefaults)

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

	local excludeMax = mini:Checkbox({
		Parent = panel,
		LabelText = "Exclude max",
		Tooltip = "Only show the current hp (exclude max hp).",
		GetValue = function ()
			return  db.ExcludeMax
		end,
		SetValue = function (value)
			db.ExcludeMax = value
		end
	})

	excludeMax:SetPoint("TOPLEFT", lines, "BOTTOMLEFT", 0, -verticalSpacing)

	local passiveModeText = "'%s' is controlling UI updates and we are running in passive mode."
	local mode = mini:TextLine({
		Parent = panel,
		Text = passiveModeText,
		Font = "GameFontRed"
	})

	mode:SetPoint("TOPLEFT", excludeMax, "BOTTOMLEFT", 0, -verticalSpacing)

	panel:HookScript("OnShow", function()
		if addon.PassiveMode then
			mode:SetText(string.format(passiveModeText, addon.PassiveModeOwner or "nil"))
			mode:Show()
		else
			mode:Hide()
		end
	end)

	mini:RegisterSlashCommand(category, panel, {
		"/minihealthnumbers",
		"/minihn",
		"/mhn",
	})
end
