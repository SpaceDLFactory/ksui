local _, ns = ...

-- Sells gray items and repairs with your own gold whenever a vendor opens.
function ns.OnMerchantShow()
	local db = ns.db
	if db.sellJunk and C_MerchantFrame.IsSellAllJunkEnabled() and C_MerchantFrame.GetNumJunkItems() > 0 then
		C_MerchantFrame.SellAllJunkItems()
		print(ns.T("검성UI: 잡템을 팔았습니다.", "KSUI: sold junk."))
	end
	if db.autoRepair and CanMerchantRepair() then
		-- The second value is false when the vendor won't repair what you have; Blizzard greys its button out then.
		local cost, canRepair = GetRepairAllCost()
		if not canRepair then
			return
		end
		if cost > 0 and cost <= GetMoney() then
			RepairAllItems()
			print(ns.T("검성UI: 수리했습니다. ", "KSUI: repaired for ") .. C_CurrencyInfo.GetCoinTextureString(cost))
		elseif cost > 0 then
			print(ns.T("검성UI: 수리비가 모자랍니다.", "KSUI: not enough gold to repair."))
		end
	end
end
