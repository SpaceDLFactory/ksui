local _, ns = ...

-- Sells gray items and repairs with your own gold whenever a vendor opens.
function ns.OnMerchantShow()
	local db = ns.db
	if db.sellJunk and C_MerchantFrame.IsSellAllJunkEnabled() and C_MerchantFrame.GetNumJunkItems() > 0 then
		C_MerchantFrame.SellAllJunkItems()
		print("검성UI: 잡템을 팔았습니다.")
	end
	if db.autoRepair and CanMerchantRepair() then
		local cost = GetRepairAllCost()
		if cost > 0 and cost <= GetMoney() then
			RepairAllItems()
			print("검성UI: 수리했습니다. " .. C_CurrencyInfo.GetCoinTextureString(cost))
		elseif cost > 0 then
			print("검성UI: 수리비가 모자랍니다.")
		end
	end
end
