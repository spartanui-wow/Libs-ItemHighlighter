local addonName, root = ... --[[@type string, table]]
local addon = root.Core
local Log = root.Log

---@class BlizzardIntegration
local BlizzardIntegration = {
	name = 'Blizzard',
}

-- Storage for our indicator frames
local indicatorFrames = {}
local hookedButtons = {}

-- Check if Blizzard bags are available (always true)
function BlizzardIntegration:IsAvailable()
	return true -- Always available as it's the default UI
end

-- Helper function to check if Blizzard bags are visible
function BlizzardIntegration:AreBagsVisible()
	-- Check combined bags frame (modern UI)
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsVisible() then
		return true
	end

	-- Check individual container frames
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		local frame = _G['ContainerFrame' .. i]
		if frame and frame:IsVisible() then
			return true
		end
	end

	-- Check bank frame
	if BankFrame and BankFrame:IsVisible() then
		return true
	end

	return false
end

-- Create indicator frame for a bag slot
local function CreateSlotIndicator(button)
	if indicatorFrames[button] then
		return indicatorFrames[button]
	end

	local frame = root.Animation.CreateIndicatorFrame(button)
	frame:SetFrameLevel(button:GetFrameLevel() + 5) -- Ensure it's above the button
	indicatorFrames[button] = frame

	Log('Created indicator frame for bag slot', 'debug')
	return frame
end

-- Update indicator for a specific bag slot
local function UpdateSlotIndicator(button)
	if not addon.DB.ShowGlow and not addon.DB.ShowIndicator then
		if indicatorFrames[button] then
			root.Animation.CleanupAnimation(indicatorFrames[button])
			indicatorFrames[button]:Hide()
		end
		return
	end

	-- Get item info from the button
	local bagID = button:GetBagID()
	local slotID = button:GetID()

	if not bagID or not slotID then
		return
	end

	local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
	if not itemLink then
		-- No item in slot, hide indicator
		if indicatorFrames[button] then
			root.Animation.CleanupAnimation(indicatorFrames[button])
			indicatorFrames[button]:Hide()
		end
		return
	end

	-- Create item details object
	local itemDetails = {
		itemLink = itemLink,
		bagID = bagID,
		slotID = slotID,
	}

	-- Get or create indicator frame
	local indicator = CreateSlotIndicator(button)

	-- Update the indicator
	local shouldShow = root.Animation.UpdateIndicatorFrame(indicator, itemDetails)
	if shouldShow then
		indicator:Show()
	else
		indicator:Hide()
	end
end

-- Hook bag slot updates
local function HookBagSlot(button)
	if hookedButtons[button] then
		return
	end

	-- Hook the button's update function
	if button.UpdateTooltip then
		hooksecurefunc(button, 'UpdateTooltip', function()
			UpdateSlotIndicator(button)
		end)
	end

	-- Also hook when items change
	local originalOnEvent = button:GetScript('OnEvent')
	button:SetScript('OnEvent', function(self, event, ...)
		if originalOnEvent then
			originalOnEvent(self, event, ...)
		end

		if event == 'BAG_UPDATE_DELAYED' or event == 'ITEM_LOCK_CHANGED' then
			UpdateSlotIndicator(self)
		end
	end)

	hookedButtons[button] = true
	Log('Hooked bag slot button events', 'debug')
end

-- Find and hook all bag slot buttons
local function HookAllBagSlots()
	-- Hook combined bags frame items (modern UI)
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsVisible() then
		if ContainerFrameCombinedBags.Items then
			for _, itemButton in pairs(ContainerFrameCombinedBags.Items) do
				if itemButton and itemButton.GetBagID and itemButton.GetID then
					HookBagSlot(itemButton)
				end
			end
		end
	end

	-- Hook individual container frames
	for bagFrameIndex = 1, NUM_CONTAINER_FRAMES or 13 do
		local containerFrame = _G['ContainerFrame' .. bagFrameIndex]
		if containerFrame and containerFrame:IsVisible() then
			-- Use the frame's item button pool if available
			if containerFrame.Items then
				for _, itemButton in pairs(containerFrame.Items) do
					if itemButton and itemButton.GetBagID and itemButton.GetID then
						HookBagSlot(itemButton)
					end
				end
			else
				-- Fallback to traditional item button naming
				local frameSize = C_Container.GetContainerNumSlots(containerFrame:GetID()) or 0
				for slotIndex = 1, frameSize do
					local itemButton = _G['ContainerFrame' .. bagFrameIndex .. 'Item' .. slotIndex]
					if itemButton then
						HookBagSlot(itemButton)
					end
				end
			end
		end
	end

	-- Hook bank slots if available
	if BankFrame and BankFrame:IsVisible() then
		-- Hook generic bank slots
		for i = 1, NUM_BANKGENERIC_SLOTS or 28 do
			local button = _G['BankFrameItem' .. i]
			if button then
				HookBagSlot(button)
			end
		end

		-- Hook reagent bank slots if available
		if ReagentBankFrame then
			for i = 1, REAGENTBANK_MAX_SLOTS or 98 do
				local button = _G['ReagentBankFrameItem' .. i]
				if button then
					HookBagSlot(button)
				end
			end
		end
	end
end

-- Refresh all indicators
local function RefreshAllIndicators()
	Log('Refreshing all Blizzard bag indicators')

	-- Update all hooked buttons
	for button in pairs(hookedButtons) do
		if button:IsVisible() then
			UpdateSlotIndicator(button)
		end
	end

	-- Make sure we have all current slots hooked
	HookAllBagSlots()
end

-- Event handler for bag updates
local function OnBagUpdate(event, bagID)
	if not BlizzardIntegration:AreBagsVisible() then
		return
	end

	Log('Bag update event: ' .. event .. (bagID and (' for bag ' .. bagID) or ''), 'debug')

	-- Refresh indicators after a short delay to ensure bag contents are updated
	addon:ScheduleTimer(RefreshAllIndicators, 0.1)
end

function BlizzardIntegration:OnEnable()
	Log('Blizzard bags integration enabling')

	-- Register for bag update events
	addon:RegisterEvent('BAG_UPDATE_DELAYED', OnBagUpdate)
	addon:RegisterEvent('BAG_UPDATE', OnBagUpdate)
	addon:RegisterEvent('ITEM_LOCK_CHANGED', OnBagUpdate)

	-- Register for container frame events
	addon:RegisterEvent('USE_COMBINED_BAGS_CHANGED', function()
		addon:ScheduleTimer(function()
			HookAllBagSlots()
			RefreshAllIndicators()
		end, 0.2)
	end)

	-- Bank events
	addon:RegisterEvent('BANKFRAME_OPENED', function()
		addon:ScheduleTimer(HookAllBagSlots, 0.1)
	end)
	addon:RegisterEvent('BANKFRAME_CLOSED', function()
		-- Clean up bank indicators
		for button, frame in pairs(indicatorFrames) do
			if button:GetParent() and button:GetParent():GetName() and string.find(button:GetParent():GetName(), 'BankFrame') then
				root.Animation.CleanupAnimation(frame)
				frame:Hide()
			end
		end
	end)

	-- Hook container frame show/hide events
	if ContainerFrameCombinedBags then
		ContainerFrameCombinedBags:HookScript('OnShow', function()
			Log('Combined bags frame shown', 'debug')
			addon:ScheduleTimer(function()
				HookAllBagSlots()
				RefreshAllIndicators()
				root.Animation.StartGlobalTimer()
			end, 0.1)
		end)

		ContainerFrameCombinedBags:HookScript('OnHide', function()
			Log('Combined bags frame hidden', 'debug')
			root.Animation.StopGlobalTimer()
		end)
	end

	-- Hook bag toggle functions
	local function OnBagToggle()
		addon:ScheduleTimer(function()
			if BlizzardIntegration:AreBagsVisible() then
				Log('Blizzard bags opened, hooking slots', 'debug')
				HookAllBagSlots()
				RefreshAllIndicators()
				root.Animation.StartGlobalTimer()
			else
				Log('Blizzard bags closed, stopping animation', 'debug')
				root.Animation.StopGlobalTimer()
			end
		end, 0.1)
	end

	hooksecurefunc('ToggleBackpack', OnBagToggle)
	hooksecurefunc('ToggleBag', OnBagToggle)
	hooksecurefunc('ToggleAllBags', OnBagToggle)

	-- Initial hook if bags are already open
	if self:AreBagsVisible() then
		HookAllBagSlots()
	end
end

function BlizzardIntegration:OnDisable()
	Log('Blizzard bags integration disabling')

	-- Clean up all indicators
	for button, frame in pairs(indicatorFrames) do
		root.Animation.CleanupAnimation(frame)
		frame:Hide()
	end
	indicatorFrames = {}
	hookedButtons = {}

	-- Unregister events
	addon:UnregisterEvent('BAG_UPDATE_DELAYED')
	addon:UnregisterEvent('BAG_UPDATE')
	addon:UnregisterEvent('ITEM_LOCK_CHANGED')
	addon:UnregisterEvent('USE_COMBINED_BAGS_CHANGED')
	addon:UnregisterEvent('BANKFRAME_OPENED')
	addon:UnregisterEvent('BANKFRAME_CLOSED')

	root.Animation.StopGlobalTimer()
end

-- Store refresh function for options
BlizzardIntegration.RefreshAllCornerWidgets = RefreshAllIndicators

-- Register this bag system
addon:RegisterBagSystem('blizzard', BlizzardIntegration)
