local addonName, root = ... --[[@type string, table]]
local addon = root.Core
local Log = root.Log

---@class BaganatorIntegration
local BaganatorIntegration = {
	name = 'Baganator',
}

-- Check if Baganator is available
function BaganatorIntegration:IsAvailable()
	return Baganator ~= nil and Baganator.API ~= nil and Baganator.API.RegisterCornerWidget ~= nil
end

-- Helper function to check if Baganator bags are visible
function BaganatorIntegration:AreBagsVisible()
	if not Baganator then
		return false
	end

	-- List of all possible frame group suffixes (skins)
	local frameGroups = { 'blizzard', 'dark', 'elvui', 'gw2_ui', 'ndui', '' }

	-- Check all possible Baganator bag frames directly
	for _, frameGroup in ipairs(frameGroups) do
		-- Check all frame types
		local frameTypes = {
			'Baganator_CategoryViewBackpackViewFrame',
			'Baganator_SingleViewBackpackViewFrame',
			'Baganator_CategoryViewBankViewFrame',
			'Baganator_SingleViewBankViewFrame',
			'Baganator_SingleViewGuildViewFrame',
		}

		for _, frameType in ipairs(frameTypes) do
			local frame = _G[frameType .. frameGroup]
			if frame and frame:IsVisible() then
				return true
			end
		end
	end

	return false
end

-- Baganator Corner Widget Functions
local function OnCornerWidgetInit(itemButton)
	local parentName = itemButton.GetName and itemButton:GetName() or 'anonymous'
	Log('[Baganator] OnCornerWidgetInit called for button: ' .. parentName, 'debug')
	local frame = root.Animation.CreateIndicatorFrame(itemButton)
	-- Ensure frame starts hidden until OnCornerWidgetUpdate explicitly shows it
	frame:Hide()
	return frame
end

local function OnCornerWidgetUpdate(cornerFrame, itemDetails)
	local frameName = cornerFrame.GetName and cornerFrame:GetName() or 'anonymous'
	local itemLink = itemDetails and itemDetails.itemLink or 'nil'
	Log('[Baganator] OnCornerWidgetUpdate called for frame: ' .. frameName .. ', itemLink: ' .. tostring(itemLink), 'debug')
	return root.Animation.UpdateIndicatorFrame(cornerFrame, itemDetails)
end

-- Function to refresh all corner widgets after settings changes
local function RefreshAllCornerWidgets()
	-- Add a small delay to ensure settings are fully applied
	addon:ScheduleTimer(function()
		if not Baganator then
			Log('Baganator not available, skipping refresh')
			return
		end

		Log('Refreshing all corner widgets due to settings change')

		-- Try to trigger Baganator's corner widget refresh
		if Baganator.API and Baganator.API.RequestItemButtonsRefresh then
			-- Modern API method
			Baganator.API.RequestItemButtonsRefresh()
			Log('Requested item buttons refresh via API')
		elseif Baganator.Core and Baganator.Core.ViewManagement then
			-- Try to refresh all views
			if Baganator.Core.ViewManagement.GetAllViews then
				local views = Baganator.Core.ViewManagement.GetAllViews()
				for _, view in pairs(views) do
					if view:IsShown() and view.RefreshItems then
						view:RefreshItems()
						Log('Refreshed view via RefreshItems')
					elseif view:IsShown() and view.UpdateView then
						view:UpdateView()
						Log('Refreshed view via UpdateView')
					end
				end
			end
		else
			-- Fallback: Force corner widget updates by clearing and re-evaluating animations
			-- This will be handled by the animation system
			Log('Using fallback refresh method')

			-- Try to trigger a bag contents update event to force refresh
			if Baganator and Baganator.API then
				-- Try to trigger a refresh via event system
				addon:ScheduleTimer(function()
					-- Force a BAG_UPDATE_DELAYED event which should refresh corner widgets
					if Baganator.API.FireBagUpdateEvent then
						Baganator.API.FireBagUpdateEvent()
						Log('Triggered BAG_UPDATE event via API')
					elseif Baganator.UnifiedBags and Baganator.UnifiedBags.RefreshBags then
						Baganator.UnifiedBags.RefreshBags()
						Log('Refreshed bags via UnifiedBags')
					end
				end, 0.05)
			end

			Log('Cleared all animations, widgets will re-evaluate on next update cycle')
		end
	end, 0.1)
end

-- Register corner widget at top level like Baganator's own widgets
if BaganatorIntegration:IsAvailable() then
	local success, err = pcall(function()
		Baganator.API.RegisterCornerWidget(
			'Openable Items', -- label
			'baganator_openable_items', -- id
			OnCornerWidgetUpdate, -- onUpdate
			OnCornerWidgetInit, -- onInit
			{ corner = 'top_right', priority = 1 }, -- defaultPosition
			false -- isFast
		)
	end)

	if not success then
		Log('Baganator corner widget registration ERROR: ' .. tostring(err), 'error')
	else
		Log('Baganator corner widget registered successfully')
	end
else
	Log('Baganator not found or API not available, cannot register corner widget', 'error')
end

function BaganatorIntegration:OnEnable()
	if not self:IsAvailable() then
		Log('Baganator not available during OnEnable', 'warning')
		return
	end

	-- Hook Blizzard bag functions that Baganator also hooks
	local function OnBagToggle()
		Log('Blizzard bag function called - checking bag state after delay', 'warning')
		addon:ScheduleTimer(function()
			if self:AreBagsVisible() then
				Log('Bags are visible after Blizzard toggle - starting timer', 'warning')
				root.Animation.StartGlobalTimer()
			else
				Log('Bags are hidden after Blizzard toggle - stopping timer', 'warning')
				root.Animation.StopGlobalTimer()
			end
		end, 0.1)
	end

	-- Hook the same functions Baganator hooks
	hooksecurefunc('ToggleBackpack', OnBagToggle)
	hooksecurefunc('ToggleBag', OnBagToggle)
	hooksecurefunc('ToggleAllBags', OnBagToggle)
end

function BaganatorIntegration:OnDisable()
	Log('Baganator integration disabling')
	root.Animation.StopGlobalTimer()
end

-- Store refresh function for options
BaganatorIntegration.RefreshAllCornerWidgets = RefreshAllCornerWidgets

-- Register this bag system
addon:RegisterBagSystem('baganator', BaganatorIntegration)
