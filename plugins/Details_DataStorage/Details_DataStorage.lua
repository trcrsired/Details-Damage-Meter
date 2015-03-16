
DETAILS_STORAGE_VERSION = 3

function _detalhes:CreateStorageDB()
	DetailsDataStorage = {
		VERSION = DETAILS_STORAGE_VERSION, 
		[14] = {}, --normal mode
		[15] = {}, --heroic mode
		[16] = {}, --mythic mode
	}
	return DetailsDataStorage
end

local f = CreateFrame ("frame", nil, UIParent)
f:Hide()
f:RegisterEvent ("ADDON_LOADED")

f:SetScript ("OnEvent", function (self, event, addonName)

	if (addonName == "Details_DataStorage") then
	
		DetailsDataStorage = DetailsDataStorage or _detalhes:CreateStorageDB()
		
		if (DetailsDataStorage.VERSION < DETAILS_STORAGE_VERSION) then
			--> do revisions
			if (DetailsDataStorage.VERSION < 3) then
				table.wipe (DetailsDataStorage)
				DetailsDataStorage = _detalhes:CreateStorageDB()
			end
		end
		
		print ("|cFFFFFF00Details! Storage|r: loaded!")
		DETAILS_STORAGE_LOADED = true
		
	end
end)

