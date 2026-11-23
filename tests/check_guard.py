"""Check that existing execution paths cannot skip the shared guard."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / "Experts"
ea = (root / "Smart_Money_Manager.mq5").read_text()
guard = (root / "AccountGuard.mqh").read_text()
entry = ea.split("bool ExecutePlan(", 1)[1].split("void QuickOrder", 1)[0]
for method in ("Buy", "Sell", "BuyLimit", "SellLimit", "BuyStop", "SellStop"):
    call = f"trade.{method}("
    assert ea.count(call) == 1 and entry.index("!GuardEntry(") < entry.index(call)
assert "PositionModify(" not in ea
assert guard.count("corrective.PositionModify(") == 1
assert "corrective.PositionModify(t,target,PositionGetDouble(POSITION_TP))" in guard
handler = ea.split("void OnTradeTransaction(", 1)[1].split("void OnChartEvent", 1)[0]
assert handler.split("{")[1].strip() == "historyDirty=true;\n  }"
assert "OrderCalcProfit(" in guard and "ACCOUNT_BALANCE" not in guard
assert not re.search(r"(POSITION|DEAL|ORDER)_MAGIC", guard)
assert re.findall(r"^input .*? (\w+)=", guard, re.M) == ["InpProtectionGraceSeconds"]
print("Panel routes, stop writer, event handler, account scope and fixed limits passed.")
reduction = guard.split("bool Reduce(", 1)[1].split("void GuardPosition", 1)[0]
assert reduction.index("RequestOutstanding(requestKey)") < reduction.index("OrderSend(req,res)")
assert reduction.index('Save(requestKey+"sending",(double)token)') < reduction.index("OrderSend(req,res)")
assert "req.volume=part" in reduction and "PositionClose(t" not in reduction
assert 'if(automatic && !RetrySlot' in reduction
