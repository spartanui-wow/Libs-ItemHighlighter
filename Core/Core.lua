local addonName, root = ... --[[@type string, table]]

-- Conflict guard: Libs-ItemHighlighter is the primary identity
-- If both are installed, only one should run
if addonName == 'BetterBags-Openable' then
	local libsIHLoaded = C_AddOns.IsAddOnLoaded('Libs-ItemHighlighter')
	if libsIHLoaded then
		return -- Libs-ItemHighlighter already running, defer to it
	end
end

-- Display name adapts based on which addon identity is running
local DISPLAY_NAMES = {
	['Libs-ItemHighlighter'] = 'Libs - Item Highlighter',
	['BetterBags-Openable'] = 'BetterBags - Openable Items',
}
local displayName = DISPLAY_NAMES[addonName] or addonName
root.displayName = displayName

-- Type definitions are located in LibsIH.definition.lua (not packaged)

---@class LibsIHCore
local addon = LibStub('AceAddon-3.0'):NewAddon(addonName, 'AceEvent-3.0', 'AceTimer-3.0', 'AceHook-3.0')

-- Make addon globally accessible
root.Core = addon

---@class LibsIH.DB.Profile
local profile = {
	FilterGenericUse = false,
	FilterToys = true,
	FilterAppearance = true,
	FilterMounts = true,
	FilterRepGain = true,
	FilterCompanion = true,
	FilterCurios = true,
	FilterDelversBounty = true,
	FilterKnowledge = true,
	FilterContainers = true,
	FilterLockboxes = true,
	FilterHousingDecor = true,
	CreatableItem = true,
	ShowGlow = true,
	ShowIndicator = true,
	AnimationCycleTime = 0.5,
	TimeBetweenCycles = 0.10,
	AnimationUpdateInterval = 0.1,
	BagSystem = 'auto',
	-- BetterBags integration
	BetterBags_EnableCategories = true,
	BetterBags_CategoryColor = { r = 0.17, g = 0.93, b = 0.93 }, -- Cyan default
	-- Custom whitelist/blacklist
	customWhitelist = {}, -- [itemID] = itemName
	customBlacklist = {}, -- [itemID] = itemName
	pageSize = 20,
	currentWhitelistPage = 1,
	currentBlacklistPage = 1,
	searchWhitelist = '',
	searchBlacklist = '',
}

-- Localization
local Localized = {
	deDE = {
		['Use: Teaches you how to summon this mount'] = 'Benutzen: Lehrt Euch, dieses Reittier herbeizurufen',
		['Use: Collect the appearance'] = 'Benutzen: Sammelt das Aussehen',
		['reputation with'] = 'Ruf bei',
		['reputation towards'] = 'Ruf bei',
	},
	esES = {
		['Use: Teaches you how to summon this mount'] = 'Uso: Te enseña a invocar esta montura',
		['Use: Collect the appearance'] = 'Uso: Recoge la apariencia',
		['reputation with'] = 'reputación con',
		['reputation towards'] = 'reputación hacia',
	},
    ruRU = {
	    ['Use: Teaches you how to summon this mount'] = 'Использование: Обучает призыву этого маунта',
	    ['Use: Collect the appearance'] = 'Использование: Собирает внешний вид',
	    ['reputation with'] = 'репутация с',
	    ['reputation towards'] = 'репутация к'
    },		
	frFR = {
		['Use: Teaches you how to summon this mount'] = 'Utilisation: Vous apprend à invoquer cette monture',
		['Use: Collect the appearance'] = "Utilisation: Collectionnez l'apparence",
		['reputation with'] = 'réputation auprès',
		['reputation towards'] = 'réputation envers',
	},
}

local Locale = GetLocale()
function GetLocaleString(key)
	if Localized[Locale] then
		return Localized[Locale][key]
	end
	return key
end

local REP_USE_TEXT = QUEST_REPUTATION_REWARD_TOOLTIP:match('%%d%s*(.-)%s*%%s') or GetLocaleString('reputation with')

-- LibAT Logger Integration
local logger = nil

-- Initialize LibAT Logger integration
local function InitializeLibATLogger()
	if LibAT and LibAT.Logger and LibAT.Logger.RegisterAddon then
		-- Register with LibAT Logger for proper external addon integration
		logger = LibAT.Logger.RegisterAddon(displayName)
		return true
	end
	return false
end

-- Logging function with LibAT integration
local function Log(msg, level)
	if logger then
		-- Use new logger object API
		logger.log(tostring(msg), level or 'info')
	end
end

-- Export utilities
root.Log = Log
root.GetLocaleString = GetLocaleString
root.REP_USE_TEXT = REP_USE_TEXT

-- Tooltip for item scanning
local Tooltip = CreateFrame('GameTooltip', 'BagOpenableTooltip', nil, 'GameTooltipTemplate')

-- Cache version: bump this when detection logic changes to auto-clear stale notOpenable cache
local CACHE_VERSION = 4

local SearchItems = {
	'Open the container',
	'Use: Open',
	'Right Click to Open',
	'Right click to open',
	'<Right Click to Open>',
	'<Right click to open>',
	ITEM_OPENABLE,
}

-- Helper function to cache and return openable result
local function CacheOpenableResult(itemID, isOpenable)
	if itemID and addon.GlobalDB and addon.GlobalDB.itemCache then
		if isOpenable then
			addon.GlobalDB.itemCache.openable[itemID] = true
			Log('Cached item ' .. itemID .. ' as openable', 'debug')
		else
			addon.GlobalDB.itemCache.notOpenable[itemID] = true
			Log('Cached item ' .. itemID .. ' as not openable', 'debug')
		end
	end
	return isOpenable
end

local function CheckItem(itemDetails)
	if not itemDetails or not itemDetails.itemLink then
		return nil
	end

	local itemLink = itemDetails.itemLink
	local bagID, slotID = itemDetails.bagID, itemDetails.slotID

	-- Get itemID for caching
	local itemID = C_Item.GetItemInfoInstant(itemLink)

	-- Check custom whitelist/blacklist FIRST (highest priority)
	if itemID and addon.DB then
		-- Whitelist: always highlight if in whitelist
		if addon.DB.customWhitelist[itemID] then
			Log('Item ' .. itemID .. ' is in custom whitelist - forcing highlight', 'debug')
			return true
		end

		-- Blacklist: never highlight if in blacklist
		if addon.DB.customBlacklist[itemID] then
			Log('Item ' .. itemID .. ' is in custom blacklist - skipping highlight', 'debug')
			return false
		end
	end

	if itemID and addon.GlobalDB and addon.GlobalDB.itemCache then
		-- Check cache first
		if addon.GlobalDB.itemCache.openable[itemID] then
			Log('Cache hit: Item ' .. itemID .. ' is openable', 'debug')
			return true
		elseif addon.GlobalDB.itemCache.notOpenable[itemID] then
			Log('Cache hit: Item ' .. itemID .. ' is not openable', 'debug')
			return false
		end
	end

	-- Quick check for common openable item types
	local itemName, _, _, _, _, itemType, itemSubType = C_Item.GetItemInfo(itemLink)

	-- Exclude non-cosmetic armor and weapon types to prevent false positives
	-- (e.g., items with "companion" in flavor text like Fangs of Ashamane)
	-- Cosmetic armor/weapons are allowed through for appearance detection
	if (itemType == 'Weapon' or itemType == 'Armor') and itemSubType ~= 'Cosmetic' then
		return CacheOpenableResult(itemID, false)
	end
	local Consumable = itemType == 'Consumable' or itemSubType == 'Consumables'

	if addon.DB.FilterDelversBounty and itemName and string.find(itemName, 'Delver') and string.find(itemName, 'Bounty') then
		return CacheOpenableResult(itemID, true)
	end

	if Consumable and itemSubType and string.find(itemSubType, 'Curio') and addon.DB.FilterCurios then
		return CacheOpenableResult(itemID, true)
	end

	if addon.DB.FilterHousingDecor and itemType == 'Housing' then
		return CacheOpenableResult(itemID, true)
	end

	-- Use tooltip scanning for detailed analysis
	Tooltip:ClearLines()
	Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	if bagID and slotID then
		Tooltip:SetBagItem(bagID, slotID)
	else
		Tooltip:SetHyperlink(itemLink)
	end

	local numLines = Tooltip:NumLines()
	Log('Tooltip has ' .. numLines .. ' lines for item: ' .. itemLink, 'debug')

	-- Track whether tooltip had enough data to trust a negative result
	local tooltipHasData = numLines >= 2

	for i = 1, numLines do
		local leftLine = _G['BagOpenableTooltipTextLeft' .. i]
		local rightLine = _G['BagOpenableTooltipTextRight' .. i]

		if leftLine then
			local LineText = leftLine:GetText()
			if LineText then
				-- Search for basic openable items
				for _, v in pairs(SearchItems) do
					if string.find(LineText, v) then
						return CacheOpenableResult(itemID, true)
					end
				end

				-- Check for containers (caches, chests, etc.)
				if
					addon.DB.FilterContainers
					and (
						string.find(LineText, 'Weekly cache')
						or string.find(LineText, 'Cache of')
						or string.find(LineText, 'Right [Cc]lick to open')
						or string.find(LineText, '<Right [Cc]lick to [Oo]pen>')
						or string.find(LineText, 'Contains')
					)
				then
					Log('Found container with right click text: ' .. LineText)
					return CacheOpenableResult(itemID, true)
				end

				if
					addon.DB.FilterAppearance
					and (string.find(LineText, ITEM_COSMETIC_LEARN) or string.find(LineText, GetLocaleString('Use: Collect the appearance')) or string.find(LineText, 'Add this appearance'))
				then
					return CacheOpenableResult(itemID, true)
				end

				-- Remove (%s). from ITEM_CREATE_LOOT_SPEC_ITEM
				local CreateItemString = ITEM_CREATE_LOOT_SPEC_ITEM:gsub(' %(%%s%)%.', '')
				if
					addon.DB.CreatableItem
					and (string.find(LineText, CreateItemString) or string.find(LineText, 'Create a soulbound item for your class') or string.find(LineText, 'item appropriate for your class'))
				then
					return CacheOpenableResult(itemID, true)
				end

				if LineText == LOCKED and addon.DB.FilterLockboxes then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterToys and string.find(LineText, ITEM_TOY_ONUSE) then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterCompanion and string.find(LineText, 'companion') then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterKnowledge and (string.find(LineText, 'Knowledge') and string.find(LineText, 'Study to increase')) then
					return CacheOpenableResult(itemID, true)
				end

				if
					addon.DB.FilterRepGain
					and (string.find(LineText, REP_USE_TEXT) or string.find(LineText, GetLocaleString('reputation towards')) or string.find(LineText, GetLocaleString('reputation with')))
					and string.find(LineText, ITEM_SPELL_TRIGGER_ONUSE)
				then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterMounts and (string.find(LineText, GetLocaleString('Use: Teaches you how to summon this mount')) or string.find(LineText, 'Drakewatcher Manuscript')) then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterGenericUse and string.find(LineText, ITEM_SPELL_TRIGGER_ONUSE) then
					return CacheOpenableResult(itemID, true)
				end
			end
		end

		if rightLine then
			local RightLineText = rightLine:GetText()
			if RightLineText then
				-- Search right side text too
				for _, v in pairs(SearchItems) do
					if string.find(RightLineText, v) then
						return CacheOpenableResult(itemID, true)
					end
				end

				-- Check right side for containers
				if addon.DB.FilterContainers and (string.find(RightLineText, 'Right [Cc]lick to open') or string.find(RightLineText, '<Right [Cc]lick to [Oo]pen>')) then
					Log('Found container with right click text: ' .. RightLineText)
					return CacheOpenableResult(itemID, true)
				end
			end
		end
	end

	-- Only cache negative results if the tooltip actually had data to scan
	if tooltipHasData then
		return CacheOpenableResult(itemID, false)
	else
		Log('Tooltip had no data for item ' .. tostring(itemID) .. ' - skipping negative cache', 'warning')
		return false
	end
end

---Debug function to explain why an item is or isn't marked as openable
---@param itemID number The item ID to debug
function addon:DebugItemOpenability(itemID)
	if not itemID then
		print('|cffFFFF00ItemHighlighter Debug:|r Item ID is required')
		return
	end

	-- Get item info
	local itemLink = select(2, C_Item.GetItemInfo(itemID))
	if not itemLink then
		print('|cffFFFF00ItemHighlighter Debug:|r Item ' .. itemID .. ' not found or not loaded')
		return
	end

	local name, _, quality, _, _, itemType, itemSubType = C_Item.GetItemInfo(itemID)
	local qualityColor = ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].hex or 'ffffffff'

	print('|cffFFFF00=== ItemHighlighter Debug ===|r')
	print(string.format('Item: |c%s%s|r (ID: %d)', qualityColor, name or 'Unknown', itemID))
	print(string.format('Type: %s / %s', itemType or 'nil', itemSubType or 'nil'))
	print(string.format('Link: %s', itemLink))

	-- Show cache status but don't return early — always run the full analysis
	if addon.GlobalDB and addon.GlobalDB.itemCache then
		if addon.GlobalDB.itemCache.openable[itemID] then
			print('|cff00FF00CACHED:|r Item was cached as openable (running full analysis below)')
		elseif addon.GlobalDB.itemCache.notOpenable[itemID] then
			print('|cffFF0000CACHED:|r Item was cached as not openable (running full analysis below)')
		else
			print('|cffFFFFFFCACHED:|r Item is not in cache')
		end
	end

	print('|cffFFFFFF--- Analysis Process ------|r')

	local foundMatch = false
	local excludedByType = false
	local suggestedFilters = {}

	-- Weapon/Armor exclusion check (mirrors CheckItem logic)
	if itemType == 'Weapon' or itemType == 'Armor' then
		local isCosmetic = itemSubType == 'Cosmetic'
		if isCosmetic then
			print('|cffFFFFFF NOTE:|r Item is ' .. itemType .. ' / Cosmetic — Armor exclusion bypassed for appearance check')
		else
			print('|cffFF0000EXCLUDED:|r Item type is ' .. itemType .. ' — excluded to prevent false positives (e.g., "companion" in flavor text)')
			print('|cffFFFFFF         Only Cosmetic armor/weapons bypass this exclusion')
			excludedByType = true
		end
	end

	-- Quick type check
	local Consumable = itemType == 'Consumable' or itemSubType == 'Consumables'
	if Consumable and itemSubType and string.find(itemSubType, 'Curio') and addon.DB.FilterCurios then
		print('|cff00FF00MATCH:|r Curio item (FilterCurios enabled)')
		foundMatch = true
	else
		print('|cffFFFFFF SKIP:|r Not a Curio or FilterCurios disabled')
	end

	if itemType == 'Housing' then
		if addon.DB.FilterHousingDecor then
			print('|cff00FF00MATCH:|r Housing Decor item (FilterHousingDecor enabled)')
			foundMatch = true
		else
			print('|cffFFAA00POTENTIAL:|r Housing Decor item found, but FilterHousingDecor is disabled')
			suggestedFilters.FilterHousingDecor = true
		end
	end

	-- Tooltip analysis
	print('|cffFFFFFF--- Tooltip Analysis ------|r')
	Tooltip:ClearLines()
	Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	Tooltip:SetHyperlink(itemLink)

	local numLines = Tooltip:NumLines()
	print(string.format('Tooltip has %d lines', numLines))
	for i = 1, numLines do
		local leftLine = _G['BagOpenableTooltipTextLeft' .. i]
		local rightLine = _G['BagOpenableTooltipTextRight' .. i]

		if leftLine then
			local LineText = leftLine:GetText()
			if LineText then
				print(string.format('  Line %d (Left): %s', i, LineText))

				-- Check SearchItems
				for _, searchText in pairs(SearchItems) do
					if string.find(LineText, searchText) then
						print(string.format('|cff00FF00MATCH:|r Found search text: "%s"', searchText))
						foundMatch = true
					end
				end

				-- Check containers
				if
					string.find(LineText, 'Weekly cache')
					or string.find(LineText, 'Cache of')
					or string.find(LineText, 'Right [Cc]lick to open')
					or string.find(LineText, '<Right [Cc]lick to [Oo]pen>')
					or string.find(LineText, 'Contains')
				then
					if addon.DB.FilterContainers then
						print('|cff00FF00MATCH:|r Container text (FilterContainers enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Container text found, but FilterContainers is disabled')
						suggestedFilters.FilterContainers = true
					end
				end

				-- Check appearance
				if string.find(LineText, ITEM_COSMETIC_LEARN) or string.find(LineText, GetLocaleString('Use: Collect the appearance')) or string.find(LineText, 'Add this appearance') then
					if addon.DB.FilterAppearance then
						print('|cff00FF00MATCH:|r Appearance item (FilterAppearance enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Appearance item found, but FilterAppearance is disabled')
						suggestedFilters.FilterAppearance = true
					end
				end

				-- Check creatable items
				local CreateItemString = ITEM_CREATE_LOOT_SPEC_ITEM:gsub(' %(%%s%)%.', '')
				if string.find(LineText, CreateItemString) or string.find(LineText, 'Create a soulbound item for your class') or string.find(LineText, 'item appropriate for your class') then
					if addon.DB.CreatableItem then
						print('|cff00FF00MATCH:|r Creatable item (CreatableItem enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Creatable item found, but CreatableItem is disabled')
						suggestedFilters.CreatableItem = true
					end
				end

				-- Check locked items
				if LineText == LOCKED then
					if addon.DB.FilterLockboxes then
						print('|cff00FF00MATCH:|r Locked item (FilterLockboxes enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Locked item found, but FilterLockboxes is disabled')
						suggestedFilters.FilterLockboxes = true
					end
				end

				-- Check toys
				if string.find(LineText, ITEM_TOY_ONUSE) then
					if addon.DB.FilterToys then
						print('|cff00FF00MATCH:|r Toy item (FilterToys enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Toy item found, but FilterToys is disabled')
						suggestedFilters.FilterToys = true
					end
				end

				-- Check companions
				if string.find(LineText, 'companion') then
					if addon.DB.FilterCompanion then
						print('|cff00FF00MATCH:|r Companion item (FilterCompanion enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Companion item found, but FilterCompanion is disabled')
						suggestedFilters.FilterCompanion = true
					end
				end

				-- Check knowledge
				if string.find(LineText, 'Knowledge') and string.find(LineText, 'Study to increase') then
					if addon.DB.FilterKnowledge then
						print('|cff00FF00MATCH:|r Knowledge item (FilterKnowledge enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Knowledge item found, but FilterKnowledge is disabled')
						suggestedFilters.FilterKnowledge = true
					end
				end

				-- Check reputation
				if
					(string.find(LineText, REP_USE_TEXT) or string.find(LineText, GetLocaleString('reputation towards')) or string.find(LineText, GetLocaleString('reputation with')))
					and string.find(LineText, ITEM_SPELL_TRIGGER_ONUSE)
				then
					if addon.DB.FilterRepGain then
						print('|cff00FF00MATCH:|r Reputation item (FilterRepGain enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Reputation item found, but FilterRepGain is disabled')
						suggestedFilters.FilterRepGain = true
					end
				end

				-- Check mounts
				if string.find(LineText, GetLocaleString('Use: Teaches you how to summon this mount')) or string.find(LineText, 'Drakewatcher Manuscript') then
					if addon.DB.FilterMounts then
						print('|cff00FF00MATCH:|r Mount item (FilterMounts enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Mount item found, but FilterMounts is disabled')
						suggestedFilters.FilterMounts = true
					end
				end

				-- Check generic use
				if string.find(LineText, ITEM_SPELL_TRIGGER_ONUSE) then
					if addon.DB.FilterGenericUse then
						print('|cff00FF00MATCH:|r Generic use item (FilterGenericUse enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Generic use item found, but FilterGenericUse is disabled')
						suggestedFilters.FilterGenericUse = true
					end
				end
			end
		end

		if rightLine then
			local RightLineText = rightLine:GetText()
			if RightLineText then
				print(string.format('  Line %d (Right): %s', i, RightLineText))

				-- Check SearchItems on right side
				for _, searchText in pairs(SearchItems) do
					if string.find(RightLineText, searchText) then
						print(string.format('|cff00FF00MATCH:|r Found search text on right: "%s"', searchText))
						foundMatch = true
					end
				end

				-- Check containers on right side
				if string.find(RightLineText, 'Right [Cc]lick to open') or string.find(RightLineText, '<Right [Cc]lick to [Oo]pen>') then
					if addon.DB.FilterContainers then
						print('|cff00FF00MATCH:|r Container text on right (FilterContainers enabled)')
						foundMatch = true
					else
						print('|cffFFAA00POTENTIAL:|r Container text found on right, but FilterContainers is disabled')
						suggestedFilters.FilterContainers = true
					end
				end
			end
		end
	end

	Tooltip:Hide()

	-- Show filter settings
	print('|cffFFFFFF--- Filter Settings ------|r')
	print(string.format('FilterContainers: %s', addon.DB.FilterContainers and 'Enabled' or 'Disabled'))
	print(string.format('FilterAppearance: %s', addon.DB.FilterAppearance and 'Enabled' or 'Disabled'))
	print(string.format('FilterToys: %s', addon.DB.FilterToys and 'Enabled' or 'Disabled'))
	print(string.format('FilterMounts: %s', addon.DB.FilterMounts and 'Enabled' or 'Disabled'))
	print(string.format('FilterRepGain: %s', addon.DB.FilterRepGain and 'Enabled' or 'Disabled'))
	print(string.format('FilterCompanion: %s', addon.DB.FilterCompanion and 'Enabled' or 'Disabled'))
	print(string.format('FilterCurios: %s', addon.DB.FilterCurios and 'Enabled' or 'Disabled'))
	print(string.format('FilterKnowledge: %s', addon.DB.FilterKnowledge and 'Enabled' or 'Disabled'))
	print(string.format('FilterLockboxes: %s', addon.DB.FilterLockboxes and 'Enabled' or 'Disabled'))
	print(string.format('FilterHousingDecor: %s', addon.DB.FilterHousingDecor and 'Enabled' or 'Disabled'))
	print(string.format('FilterGenericUse: %s', addon.DB.FilterGenericUse and 'Enabled' or 'Disabled'))
	print(string.format('CreatableItem: %s', addon.DB.CreatableItem and 'Enabled' or 'Disabled'))

	-- Show suggestions
	if next(suggestedFilters) then
		print('|cffFFFFFF--- Suggestions ------|r')
		print('|cffFFAA00To make this item openable, try enabling these filters:|r')
		for filterName, _ in pairs(suggestedFilters) do
			print('  • ' .. filterName)
		end
	end

	-- Final result
	print('|cffFFFFFF--- Final Result ------|r')
	if excludedByType and not foundMatch then
		print('|cffFF0000RESULT:|r Item is excluded by type (' .. itemType .. ') — tooltip matches are ignored')
	elseif foundMatch then
		print('|cff00FF00RESULT:|r Item should be highlighted as openable')
	else
		if next(suggestedFilters) then
			print('|cffFFAA00RESULT:|r Item would be openable if suggested filters were enabled')
		else
			print('|cffFF0000RESULT:|r Item should NOT be highlighted (no matching criteria)')
		end
	end
end

---Helper function to parse item input (accepts item ID, item link, or item name)
---@param input string|number The input to parse (item ID, link, or name)
---@return number|nil itemID The parsed item ID, or nil if invalid
---@return string|nil itemName The item name, or nil if not found
function addon:ParseItemInput(input)
	if not input or input == '' then
		return nil, nil
	end

	-- Try to parse as item ID (number)
	local itemID = tonumber(input)
	if itemID then
		local itemName = C_Item.GetItemNameByID(itemID)
		if itemName then
			return itemID, itemName
		else
			-- Item ID exists but not loaded yet - queue it and return
			C_Item.RequestLoadItemDataByID(itemID)
			return itemID, 'Loading...'
		end
	end

	-- Try to parse as item link
	local linkItemID = tonumber(string.match(input, 'item:(%d+)'))
	if linkItemID then
		local itemName = C_Item.GetItemNameByID(linkItemID)
		if itemName then
			return linkItemID, itemName
		else
			C_Item.RequestLoadItemDataByID(linkItemID)
			return linkItemID, 'Loading...'
		end
	end

	-- Try to lookup by item name (less reliable)
	-- This searches for exact match in cache
	local searchName = string.lower(input)
	for cachedItemID, _ in pairs(addon.GlobalDB.itemCache.openable) do
		local cachedName = C_Item.GetItemNameByID(cachedItemID)
		if cachedName and string.lower(cachedName) == searchName then
			return cachedItemID, cachedName
		end
	end

	-- Could not parse - return nil
	return nil, nil
end

-- New function: Returns category string for BetterBags integration
---@param itemDetails table Item details with itemLink, bagID, slotID
---@return string|nil categoryName The category name or nil if not openable
local function CheckItemWithCategory(itemDetails)
	if not itemDetails or not itemDetails.itemLink then
		return nil
	end

	local itemLink = itemDetails.itemLink
	local bagID, slotID = itemDetails.bagID, itemDetails.slotID
	local itemID = C_Item.GetItemInfoInstant(itemLink)

	-- Check custom whitelist/blacklist FIRST
	if itemID and addon.DB then
		if addon.DB.customWhitelist[itemID] then
			return 'Whitelist Items'
		end
		if addon.DB.customBlacklist[itemID] then
			return nil
		end
	end

	-- Quick check for common openable item types
	local itemName, _, _, _, _, itemType, itemSubType = C_Item.GetItemInfo(itemLink)

	-- Exclude non-cosmetic armor/weapons
	if (itemType == 'Weapon' or itemType == 'Armor') and itemSubType ~= 'Cosmetic' then
		return nil
	end

	local Consumable = itemType == 'Consumable' or itemSubType == 'Consumables'

	-- Quick checks
	if addon.DB.FilterDelversBounty and itemName and string.find(itemName, 'Delver') and string.find(itemName, 'Bounty') then
		return "Delver's Bounty"
	end

	if Consumable and itemSubType and string.find(itemSubType, 'Curio') and addon.DB.FilterCurios then
		return 'Curios'
	end

	if addon.DB.FilterHousingDecor and itemType == 'Housing' then
		return 'Housing Decor'
	end

	-- Tooltip scanning
	Tooltip:ClearLines()
	Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	if bagID and slotID then
		Tooltip:SetBagItem(bagID, slotID)
	else
		Tooltip:SetHyperlink(itemLink)
	end

	for i = 1, Tooltip:NumLines() do
		local leftLine = _G['BagOpenableTooltipTextLeft' .. i]
		if leftLine then
			local LineText = leftLine:GetText()
			if LineText then
				-- Check each category in priority order

				-- Basic openable items (highest priority)
				for _, v in pairs(SearchItems) do
					if string.find(LineText, v) then
						return 'Openable'
					end
				end

				-- Lockboxes
				if LineText == LOCKED and addon.DB.FilterLockboxes then
					return 'Lockboxes'
				end

				-- Cosmetics/Appearance
				if
					addon.DB.FilterAppearance
					and (string.find(LineText, ITEM_COSMETIC_LEARN) or string.find(LineText, GetLocaleString('Use: Collect the appearance')) or string.find(LineText, 'Add this appearance'))
				then
					return 'Cosmetics'
				end

				-- Creatable Items
				local CreateItemString = ITEM_CREATE_LOOT_SPEC_ITEM:gsub(' %(%%s%)%.', '')
				if
					addon.DB.CreatableItem
					and (string.find(LineText, CreateItemString) or string.find(LineText, 'Create a soulbound item for your class') or string.find(LineText, 'item appropriate for your class'))
				then
					return 'Creatable Items'
				end

				-- Toys
				if addon.DB.FilterToys and string.find(LineText, ITEM_TOY_ONUSE) then
					return 'Toys'
				end

				-- Pets/Companions
				if addon.DB.FilterCompanion and string.find(LineText, 'companion') then
					return 'Pets'
				end

				-- Knowledge
				if addon.DB.FilterKnowledge and (string.find(LineText, 'Knowledge') and string.find(LineText, 'Study to increase')) then
					return 'Knowledge'
				end

				-- Reputation
				if
					addon.DB.FilterRepGain
					and (string.find(LineText, REP_USE_TEXT) or string.find(LineText, GetLocaleString('reputation towards')) or string.find(LineText, GetLocaleString('reputation with')))
					and string.find(LineText, ITEM_SPELL_TRIGGER_ONUSE)
				then
					return 'Reputation'
				end

				-- Mounts
				if addon.DB.FilterMounts and (string.find(LineText, GetLocaleString('Use: Teaches you how to summon this mount')) or string.find(LineText, 'Drakewatcher Manuscript')) then
					return 'Mounts'
				end

				-- Containers (caches, etc.)
				if addon.DB.FilterContainers and (string.find(LineText, 'Weekly cache') or string.find(LineText, 'Cache of') or string.find(LineText, 'Contains')) then
					return 'Containers'
				end

				-- Generic Use (checked last)
				if addon.DB.FilterGenericUse and string.find(LineText, ITEM_SPELL_TRIGGER_ONUSE) then
					return 'Generic Use Items'
				end
			end
		end

		-- Check right side text too
		local rightLine = _G['BagOpenableTooltipTextRight' .. i]
		if rightLine then
			local RightLineText = rightLine:GetText()
			if RightLineText then
				-- Basic openable items
				for _, v in pairs(SearchItems) do
					if string.find(RightLineText, v) then
						return 'Openable'
					end
				end

				-- Containers
				if addon.DB.FilterContainers and (string.find(RightLineText, 'Right [Cc]lick to open') or string.find(RightLineText, '<Right [Cc]lick to [Oo]pen>')) then
					return 'Containers'
				end
			end
		end
	end

	return nil
end

-- Function to scan all bags and count items by category
---@return table statistics Table with category names as keys and counts as values
local function GetItemStatistics()
	local stats = {
		['Openable'] = 0,
		['Lockboxes'] = 0,
		['Cosmetics'] = 0,
		['Toys'] = 0,
		['Mounts'] = 0,
		['Pets'] = 0,
		['Knowledge'] = 0,
		['Curios'] = 0,
		['Creatable Items'] = 0,
		['Reputation'] = 0,
		['Containers'] = 0,
		['Generic Use Items'] = 0,
		["Delver's Bounty"] = 0,
		['Housing Decor'] = 0,
		['Whitelist Items'] = 0,
	}

	-- Scan all bag slots
	for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
		local numSlots = C_Container.GetContainerNumSlots(bagID)
		if numSlots then
			for slotID = 1, numSlots do
				local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
				if itemLink then
					local itemDetails = {
						itemLink = itemLink,
						bagID = bagID,
						slotID = slotID,
					}
					local category = CheckItemWithCategory(itemDetails)
					if category and stats[category] then
						stats[category] = stats[category] + 1
					end
				end
			end
		end
	end

	-- Scan bank if it's open
	if addon.DB and addon.DB.scanBank then
		for bagID = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
			local numSlots = C_Container.GetContainerNumSlots(bagID)
			if numSlots then
				for slotID = 1, numSlots do
					local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
					if itemLink then
						local itemDetails = {
							itemLink = itemLink,
							bagID = bagID,
							slotID = slotID,
						}
						local category = CheckItemWithCategory(itemDetails)
						if category and stats[category] then
							stats[category] = stats[category] + 1
						end
					end
				end
			end
		end
	end

	return stats
end

-- Export the item checking functions
root.CheckItem = CheckItem
root.CheckItemWithCategory = CheckItemWithCategory
root.GetItemStatistics = GetItemStatistics

-- Bag system registry - exposed as addon.BagSystems for global access
addon.BagSystems = {}

function addon:RegisterBagSystem(name, integration)
	self.BagSystems[name] = integration
	Log('Registered bag system: ' .. name)
end

function addon:GetAllAvailableBagSystems()
	local availableSystems = {}

	Log('Scanning for all available bag systems...')

	-- Check all registered systems - integrate with everything that's available
	for name, integration in pairs(self.BagSystems) do
		if integration and integration.IsAvailable and integration:IsAvailable() then
			Log('Found available bag system: ' .. name)
			table.insert(availableSystems, { name = name, integration = integration })
		end
	end

	if #availableSystems > 0 then
		local systemNames = {}
		for _, system in ipairs(availableSystems) do
			table.insert(systemNames, system.name)
		end
		Log('Will integrate with all available systems: ' .. table.concat(systemNames, ', '))
	else
		Log('No bag systems detected')
	end

	return availableSystems
end

function addon:IsBagSystemAvailable(name)
	local integration = self.BagSystems[name]
	if integration and integration.IsAvailable then
		return integration:IsAvailable()
	end
	return false
end

-- Legacy function for compatibility - now returns first available system or nil
function addon:GetActiveBagSystem()
	local systemName = self.DB.BagSystem

	if systemName == 'auto' then
		local availableSystems = self:GetAllAvailableBagSystems()
		return #availableSystems > 0 and availableSystems[1].integration or nil
	else
		-- Manual selection - respect user's choice for single system
		Log('Using manually selected bag system: ' .. systemName)
		return self.BagSystems[systemName]
	end
end

function addon:OnInitialize()
	-- Initialize SpartanUI Logger first
	InitializeLibATLogger()

	Log('LibsIH core initializing...')
	if logger then
		Log('Registered with SpartanUI Logger system')
	end
	-- Setup DB with global cache
	---@class LibsIH.DB
	local defaults = {
		profile = profile,
		global = {
			itemCache = {
				openable = {}, -- itemID -> true for confirmed openable items
				notOpenable = {}, -- itemID -> true for confirmed non-openable items
			},
		},
	}
	self.DataBase = LibStub('AceDB-3.0'):New('LibsIHDB', defaults, true) ---@type LibsIH.DB
	self.DB = self.DataBase.profile
	self.GlobalDB = self.DataBase.global
	Log('Database initialized with ShowGlow: ' .. tostring(self.DB.ShowGlow) .. ', ShowIndicator: ' .. tostring(self.DB.ShowIndicator))

	-- Auto-clear stale notOpenable cache when detection logic changes
	if self.GlobalDB.cacheVersion ~= CACHE_VERSION then
		local oldCount = 0
		if self.GlobalDB.itemCache and self.GlobalDB.itemCache.notOpenable then
			for _ in pairs(self.GlobalDB.itemCache.notOpenable) do
				oldCount = oldCount + 1
			end
			self.GlobalDB.itemCache.notOpenable = {}
		end
		self.GlobalDB.cacheVersion = CACHE_VERSION
		Log('Cache version updated to ' .. CACHE_VERSION .. ' - cleared ' .. oldCount .. ' stale notOpenable entries')
	end

	-- Initialize Libs-AddonTools ProfileManager integration
	if LibsAddonTools and LibsAddonTools.ProfileManager and LibsAddonTools.ProfileManager.IsProfileManagerAvailable() then
		self.ProfileManager = LibsAddonTools.ProfileManager.RegisterAddon(displayName, self.DataBase)
		Log('ProfileManager integration enabled - profile export/import available')
	else
		Log('LibsAddonTools not available - profile features disabled', 'info')
	end

	-- Setup options panel
	self:SetupOptions()
end

function addon:OnEnable()
	Log('LibsIH core enabling...')

	-- Store enabled systems for later cleanup
	self.enabledBagSystems = {}

	-- Enable all available bag systems
	local availableSystems = self:GetAllAvailableBagSystems()
	if #availableSystems > 0 then
		for _, systemData in ipairs(availableSystems) do
			local integration = systemData.integration
			local name = systemData.name

			Log('Enabling bag system: ' .. name)
			if integration.OnEnable then
				local success, error = pcall(function()
					integration:OnEnable()
				end)

				if success then
					table.insert(self.enabledBagSystems, integration)
					Log('Successfully enabled ' .. name .. ' integration')
				else
					Log('Failed to enable ' .. name .. ' integration: ' .. tostring(error), 'error')
				end
			else
				Log('Warning: ' .. name .. ' integration has no OnEnable method', 'warning')
			end
		end

		Log('Enabled ' .. #self.enabledBagSystems .. ' bag system integrations')
	else
		Log('No compatible bag systems found', 'warning')
	end
end

function addon:OnDisable()
	Log('LibsIH core disabling...')

	-- Stop global animation timer and cleanup all widgets
	root.Animation.StopGlobalTimer()
	root.Animation.CleanupAllWidgets()

	-- Disable all enabled bag systems
	if self.enabledBagSystems then
		for _, integration in ipairs(self.enabledBagSystems) do
			if integration.OnDisable then
				local success, error = pcall(function()
					integration:OnDisable()
				end)

				if not success then
					Log('Error disabling bag system integration: ' .. tostring(error), 'error')
				end
			end
		end
		Log('Disabled ' .. #self.enabledBagSystems .. ' bag system integrations')
		self.enabledBagSystems = {}
	end

	-- Cancel any running timers
	self:CancelAllTimers()
end

-- Options will be set up in a separate file
function addon:SetupOptions()
	-- This will be implemented in Core/Options.lua
end
