local addonName, root = ... --[[@type string, table]]
local addon = root.Core
local Log = root.Log

-- Helper function to truncate text to word count
local function TruncateToWords(text, wordCount)
	if not text then
		return ''
	end

	local words = {}
	for word in string.gmatch(text, '%S+') do
		table.insert(words, word)
		if #words >= wordCount then
			break
		end
	end

	local truncated = table.concat(words, ' ')
	if #words >= wordCount and text ~= truncated then
		truncated = truncated .. '...'
	end

	return truncated
end

-- Build dynamic item list for whitelist/blacklist
---@param listName string The database field name ('customWhitelist' or 'customBlacklist')
---@param displayName string The display name for the list ('Whitelist' or 'Blacklist')
---@param optionTable table The parent options table to populate
local function buildItemList(listName, displayName, optionTable)
	local isWhitelist = listName == 'customWhitelist'
	local searchField = isWhitelist and 'searchWhitelist' or 'searchBlacklist'
	local pageField = isWhitelist and 'currentWhitelistPage' or 'currentBlacklistPage'
	local targetList = isWhitelist and 'customBlacklist' or 'customWhitelist'
	local buttonText = isWhitelist and 'Move to Blacklist' or 'Move to Whitelist'

	-- Get the data source
	local dataSource = addon.DB[listName]
	local searchTerm = string.lower(addon.DB[searchField] or '')

	-- Build filtered list of items
	local filteredItems = {}
	for itemID, itemName in pairs(dataSource) do
		if searchTerm == '' or string.find(string.lower(itemName), searchTerm, 1, true) then
			table.insert(filteredItems, {id = itemID, name = itemName})
		end
	end

	-- Sort by name
	table.sort(filteredItems, function(a, b)
		return a.name < b.name
	end)

	-- Calculate pagination
	local pageSize = addon.DB.pageSize or 20
	local totalItems = #filteredItems
	local totalPages = math.max(1, math.ceil(totalItems / pageSize))
	local currentPage = math.min(addon.DB[pageField] or 1, totalPages)
	addon.DB[pageField] = currentPage

	local startIdx = (currentPage - 1) * pageSize + 1
	local endIdx = math.min(currentPage * pageSize, totalItems)

	-- Clear existing list args
	if not optionTable.args.list then
		optionTable.args.list = {
			type = 'group',
			inline = true,
			name = 'Items',
			order = 3,
			args = {}
		}
	end
	optionTable.args.list.args = {}

	local listOpts = optionTable.args.list.args

	-- Add page info
	listOpts.pageInfo = {
		type = 'description',
		name = string.format('Page %d of %d (%d items)', currentPage, totalPages, totalItems),
		order = 1,
		fontSize = 'medium'
	}

	-- Add search box
	listOpts.search = {
		type = 'input',
		name = 'Search',
		desc = 'Filter items by name',
		width = 'full',
		order = 2,
		get = function()
			return addon.DB[searchField]
		end,
		set = function(_, value)
			addon.DB[searchField] = value
			addon.DB[pageField] = 1 -- Reset to page 1 on search
			buildItemList(listName, displayName, optionTable)
		end
	}

	-- Add pagination controls
	listOpts.prevPage = {
		type = 'execute',
		name = 'Previous Page',
		width = 'half',
		order = 3,
		disabled = currentPage <= 1,
		func = function()
			addon.DB[pageField] = currentPage - 1
			buildItemList(listName, displayName, optionTable)
		end
	}

	listOpts.nextPage = {
		type = 'execute',
		name = 'Next Page',
		width = 'half',
		order = 4,
		disabled = currentPage >= totalPages,
		func = function()
			addon.DB[pageField] = currentPage + 1
			buildItemList(listName, displayName, optionTable)
		end
	}

	-- Add separator
	listOpts.separator = {
		type = 'header',
		name = '',
		order = 5
	}

	-- Add items for current page
	if totalItems == 0 then
		listOpts.empty = {
			type = 'description',
			name = '|cffFFAA00No items in ' .. string.lower(displayName) .. '|r',
			order = 10
		}
	else
		for i = startIdx, endIdx do
			local item = filteredItems[i]
			local itemID = item.id
			local itemName = item.name
			local count = i - startIdx

			-- Get item icon
			local itemIcon = C_Item.GetItemIconByID(itemID) or 134400
			local displayText = string.format('|T%s:16|t %s (ID: %d)', itemIcon, TruncateToWords(itemName, 10), itemID)

			-- Item label
			listOpts[tostring(itemID) .. 'label'] = {
				type = 'description',
				name = displayText,
				width = 'double',
				order = count * 3 + 10,
				fontSize = 'medium'
			}

			-- Delete button
			listOpts[tostring(itemID) .. 'delete'] = {
				type = 'execute',
				name = 'Delete',
				width = 'half',
				order = count * 3 + 11,
				func = function()
					addon.DB[listName][itemID] = nil
					buildItemList(listName, displayName, optionTable)

					-- Refresh bags
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end
			}

			-- Move button
			listOpts[tostring(itemID) .. 'move'] = {
				type = 'execute',
				name = buttonText,
				width = 'half',
				order = count * 3 + 12,
				func = function()
					-- Move to other list
					addon.DB[targetList][itemID] = itemName
					addon.DB[listName][itemID] = nil

					-- Rebuild both lists
					buildItemList(listName, displayName, optionTable)
					if isWhitelist then
						-- Also rebuild blacklist if it exists
						local blacklistTable = GetOptions().args.customLists.args.Blacklist
						if blacklistTable then
							buildItemList('customBlacklist', 'Blacklist', blacklistTable)
						end
					else
						-- Also rebuild whitelist if it exists
						local whitelistTable = GetOptions().args.customLists.args.Whitelist
						if whitelistTable then
							buildItemList('customWhitelist', 'Whitelist', whitelistTable)
						end
					end

					-- Refresh bags
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end
			}
		end
	end
end

-- AceOptions Configuration
local function GetOptions()
	return {
		name = "Lib's - Item Highlighter",
		type = 'group',
		args = {
			bagSystemHeader = {
				type = 'header',
				name = 'General Settings',
				order = 5
			},
			bagSystemSelect = {
				type = 'select',
				name = 'Bag System',
				desc = 'Choose which bag addon to integrate with',
				values = {
					auto = 'Auto-detect',
					baganator = 'Baganator',
					bagnon = 'Bagnon',
					betterbags = 'BetterBags',
					elvui = 'ElvUI',
					blizzard = 'Blizzard Default',
					adibags = 'AdiBags'
				},
				get = function()
					return addon.DB.BagSystem
				end,
				set = function(_, value)
					addon.DB.BagSystem = value
					-- Refresh the bag system
					addon:OnDisable()
					addon:OnEnable()
				end,
				order = 6
			},
			showGlow = {
				type = 'toggle',
				name = 'Show Glow Animation',
				desc = 'Display animated blue-to-green glow effect on openable items',
				get = function()
					return addon.DB.ShowGlow
				end,
				set = function(_, value)
					addon.DB.ShowGlow = value
					-- Refresh all widgets when glow is toggled
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 10
			},
			showIndicator = {
				type = 'toggle',
				name = 'Show Indicator Icon',
				desc = 'Display static treasure map icon on openable items',
				get = function()
					return addon.DB.ShowIndicator
				end,
				set = function(_, value)
					addon.DB.ShowIndicator = value
					-- Refresh all widgets when indicator is toggled
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 11
			},
			filterHeader = {
				type = 'header',
				name = 'Item Type Filters',
				order = 20
			},
			filterDesc = {
				type = 'description',
				name = 'Choose which types of openable items to highlight:',
				order = 21
			},
			filterToys = {
				type = 'toggle',
				name = 'Toys',
				desc = 'Highlight toy items that can be learned',
				get = function()
					return addon.DB.FilterToys
				end,
				set = function(_, value)
					addon.DB.FilterToys = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 30
			},
			filterAppearance = {
				type = 'toggle',
				name = 'Appearances',
				desc = 'Highlight items that teach appearances/transmog',
				get = function()
					return addon.DB.FilterAppearance
				end,
				set = function(_, value)
					addon.DB.FilterAppearance = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 31
			},
			filterMounts = {
				type = 'toggle',
				name = 'Mounts',
				desc = 'Highlight mount teaching items',
				get = function()
					return addon.DB.FilterMounts
				end,
				set = function(_, value)
					addon.DB.FilterMounts = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 32
			},
			filterCompanion = {
				type = 'toggle',
				name = 'Companions/Pets',
				desc = 'Highlight companion and pet items',
				get = function()
					return addon.DB.FilterCompanion
				end,
				set = function(_, value)
					addon.DB.FilterCompanion = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 33
			},
			filterRepGain = {
				type = 'toggle',
				name = 'Reputation Items',
				desc = 'Highlight items that give reputation',
				get = function()
					return addon.DB.FilterRepGain
				end,
				set = function(_, value)
					addon.DB.FilterRepGain = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 34
			},
			filterCurios = {
				type = 'toggle',
				name = 'Curios',
				desc = 'Highlight curio items',
				get = function()
					return addon.DB.FilterCurios
				end,
				set = function(_, value)
					addon.DB.FilterCurios = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 35
			},
			filterContainers = {
				type = 'toggle',
				name = 'Containers',
				desc = "Highlight containers with 'Right click to open' text (caches, chests, etc.)",
				get = function()
					return addon.DB.FilterContainers
				end,
				set = function(_, value)
					addon.DB.FilterContainers = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 36
			},
			filterKnowledge = {
				type = 'toggle',
				name = 'Knowledge Items',
				desc = 'Highlight knowledge/profession learning items',
				get = function()
					return addon.DB.FilterKnowledge
				end,
				set = function(_, value)
					addon.DB.FilterKnowledge = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 37
			},
			filterCreatable = {
				type = 'toggle',
				name = 'Creatable Items',
				desc = 'Highlight items that create class-specific gear',
				get = function()
					return addon.DB.CreatableItem
				end,
				set = function(_, value)
					addon.DB.CreatableItem = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 38
			},
			filterGeneric = {
				type = 'toggle',
				name = 'Generic Use Items',
				desc = "Highlight generic 'Use:' items (may be noisy)",
				get = function()
					return addon.DB.FilterGenericUse
				end,
				set = function(_, value)
					addon.DB.FilterGenericUse = value
					-- Reset cache since filter criteria changed
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 39
			},
			cacheHeader = {
				type = 'header',
				name = 'Cache Management',
				order = 40
			},
			resetCache = {
				type = 'execute',
				name = 'Reset Item Cache',
				desc = 'Clear all cached item openability data. Use this if items are incorrectly cached.',
				func = function()
					local openableCount = 0
					local notOpenableCount = 0

					-- Count items before clearing
					for _ in pairs(addon.GlobalDB.itemCache.openable) do
						openableCount = openableCount + 1
					end
					for _ in pairs(addon.GlobalDB.itemCache.notOpenable) do
						notOpenableCount = notOpenableCount + 1
					end

					-- Clear cache
					addon.GlobalDB.itemCache.openable = {}
					addon.GlobalDB.itemCache.notOpenable = {}

					Log('Cache reset: cleared ' .. openableCount .. ' openable items and ' .. notOpenableCount .. ' not openable items')
					print("Lib's - Item Highlighter: Cache reset - cleared " .. (openableCount + notOpenableCount) .. ' cached items')

					-- Refresh widgets to re-evaluate items
					local bagSystem = addon:GetActiveBagSystem()
					if bagSystem and bagSystem.RefreshAllCornerWidgets then
						bagSystem.RefreshAllCornerWidgets()
					end
				end,
				order = 41
			},
			debugHeader = {
				type = 'header',
				name = 'Item Debug Tools',
				order = 42
			},
			debugInput = {
				type = 'input',
				name = 'Item ID to Debug',
				desc = 'Enter an item ID to debug why it is or isn\'t marked as openable',
				get = function()
					return addon.debugItemID or ''
				end,
				set = function(_, value)
					addon.debugItemID = value
				end,
				order = 43
			},
			debugExecute = {
				type = 'execute',
				name = 'Debug Item',
				desc = 'Analyze the specified item ID and explain why it is or isn\'t openable',
				func = function()
					local itemID = tonumber(addon.debugItemID)
					if itemID then
						addon:DebugItemOpenability(itemID)
					else
						print('|cffFFFF00ItemHighlighter:|r Please enter a valid item ID')
					end
				end,
				order = 44
			},
			customListsHeader = {
				type = 'header',
				name = 'Custom Item Lists',
				order = 45
			},
			customListsDesc = {
				type = 'description',
				name = 'Add items to force them to be highlighted (whitelist) or never highlighted (blacklist). You can enter an item ID, paste an item link, or type an item name.',
				order = 46
			},
			customLists = {
				type = 'group',
				name = 'Custom Lists',
				childGroups = 'tab',
				order = 47,
				args = {
					Whitelist = {
						type = 'group',
						name = 'Whitelist (Always Highlight)',
						order = 1,
						args = {
							description = {
								type = 'description',
								name = 'Items in the whitelist will ALWAYS be highlighted, regardless of filter settings.',
								order = 1
							},
							create = {
								type = 'input',
								name = 'Add Item to Whitelist',
								desc = 'Enter an item ID, item link, or item name',
								width = 'full',
								order = 2,
								get = function()
									return ''
								end,
								set = function(_, input)
									if input and input ~= '' then
										local itemID, itemName = addon:ParseItemInput(input)
										if itemID then
											addon.DB.customWhitelist[itemID] = itemName
											buildItemList('customWhitelist', 'Whitelist', GetOptions().args.customLists.args.Whitelist)
											print("|cff00FF00Added to whitelist:|r " .. (itemName or 'Item ' .. itemID))

											-- Refresh bags
											local bagSystem = addon:GetActiveBagSystem()
											if bagSystem and bagSystem.RefreshAllCornerWidgets then
												bagSystem.RefreshAllCornerWidgets()
											end
										else
											print('|cffFF0000Invalid item input:|r Could not find item: ' .. input)
										end
									end
								end
							},
							pageSize = {
								type = 'range',
								name = 'Items Per Page',
								desc = 'Number of items to show per page',
								min = 10,
								max = 50,
								step = 5,
								order = 2.5,
								get = function()
									return addon.DB.pageSize
								end,
								set = function(_, value)
									addon.DB.pageSize = value
									addon.DB.currentWhitelistPage = 1
									buildItemList('customWhitelist', 'Whitelist', GetOptions().args.customLists.args.Whitelist)
								end
							}
						}
					},
					Blacklist = {
						type = 'group',
						name = 'Blacklist (Never Highlight)',
						order = 2,
						args = {
							description = {
								type = 'description',
								name = 'Items in the blacklist will NEVER be highlighted, even if they match filter criteria.',
								order = 1
							},
							create = {
								type = 'input',
								name = 'Add Item to Blacklist',
								desc = 'Enter an item ID, item link, or item name',
								width = 'full',
								order = 2,
								get = function()
									return ''
								end,
								set = function(_, input)
									if input and input ~= '' then
										local itemID, itemName = addon:ParseItemInput(input)
										if itemID then
											addon.DB.customBlacklist[itemID] = itemName
											buildItemList('customBlacklist', 'Blacklist', GetOptions().args.customLists.args.Blacklist)
											print("|cffFF0000Added to blacklist:|r " .. (itemName or 'Item ' .. itemID))

											-- Refresh bags
											local bagSystem = addon:GetActiveBagSystem()
											if bagSystem and bagSystem.RefreshAllCornerWidgets then
												bagSystem.RefreshAllCornerWidgets()
											end
										else
											print('|cffFF0000Invalid item input:|r Could not find item: ' .. input)
										end
									end
								end
							},
							pageSize = {
								type = 'range',
								name = 'Items Per Page',
								desc = 'Number of items to show per page',
								min = 10,
								max = 50,
								step = 5,
								order = 2.5,
								get = function()
									return addon.DB.pageSize
								end,
								set = function(_, value)
									addon.DB.pageSize = value
									addon.DB.currentBlacklistPage = 1
									buildItemList('customBlacklist', 'Blacklist', GetOptions().args.customLists.args.Blacklist)
								end
							}
						}
					}
				}
			},
			animationHeader = {
				type = 'header',
				name = 'Animation Settings',
				order = 50
			},
			animationGroup = {
				type = 'group',
				name = 'Animation Timing',
				inline = true,
				order = 51,
				args = {
					cycleTime = {
						type = 'range',
						name = 'Cycle Time',
						desc = 'Time to fade from one color to another (seconds)',
						min = 0.1,
						max = 6.0,
						step = 0.05,
						get = function()
							return addon.DB.AnimationCycleTime
						end,
						set = function(_, value)
							addon.DB.AnimationCycleTime = value
						end,
						order = 1
					},
					betweenCycles = {
						type = 'range',
						name = 'Pause Between Cycles',
						desc = 'Time to pause at each color (seconds)',
						min = 0.1,
						max = 6.0,
						step = 0.05,
						get = function()
							return addon.DB.TimeBetweenCycles
						end,
						set = function(_, value)
							addon.DB.TimeBetweenCycles = value
						end,
						order = 2
					},
					updateInterval = {
						type = 'range',
						name = 'Update Interval',
						desc = 'How often to update the animation (seconds) - lower = smoother',
						min = 0.1,
						max = 6.0,
						step = 0.05,
						get = function()
							return addon.DB.AnimationUpdateInterval
						end,
						set = function(_, value)
							addon.DB.AnimationUpdateInterval = value
						end,
						order = 3
					}
				}
			}
		}
	}
end

function addon:SetupOptions()
	local optionsTable = GetOptions()
	LibStub('AceConfig-3.0'):RegisterOptionsTable('LibsItemHighlighter', optionsTable)
	LibStub('AceConfigDialog-3.0'):AddToBlizOptions('LibsItemHighlighter', "Lib's - Item Highlighter")
	Log('Options panel registered with Blizzard Interface')

	-- Initialize the custom lists
	buildItemList('customWhitelist', 'Whitelist', optionsTable.args.customLists.args.Whitelist)
	buildItemList('customBlacklist', 'Blacklist', optionsTable.args.customLists.args.Blacklist)

	-- Register slash commands
	SLASH_LIBSITEMHIGHLIGHTER1 = '/libsih'
	SLASH_LIBSITEMHIGHLIGHTER2 = '/itemhighlighter'
	SlashCmdList['LIBSITEMHIGHLIGHTER'] = function(msg)
		if msg == 'profile' then
			if addon.ProfileManager then
				addon.ProfileManager:ShowWindow()
			else
				print("Lib's - Item Highlighter: ProfileManager not available (LibsAddonTools required)")
			end
		else
			Settings.OpenToCategory("Lib's - Item Highlighter")
		end
	end

	-- Add profile management commands if LibsAddonTools is available
	if addon.ProfileManager then
		SLASH_LIBSIHPROFILE1 = '/ihprofile'
		SlashCmdList['LIBSIHPROFILE'] = function(msg)
			if msg == 'export' then
				local exported = addon.ProfileManager:ExportProfile('text')
				if exported then
					print("Lib's - Item Highlighter profile exported:")
					print(exported)
				else
					print("Failed to export profile")
				end
			elseif msg:match('^import ') then
				local importString = msg:match('^import (.+)')
				if importString and importString ~= '' then
					local success = addon.ProfileManager:ImportProfile(importString)
					if success then
						print("Profile imported successfully!")
					else
						print("Failed to import profile")
					end
				else
					print("Usage: /ihprofile import <profile_string>")
				end
			else
				addon.ProfileManager:ShowWindow()
			end
		end
		Log('Profile management commands registered: /ihprofile, /libsih profile')
	end
end
