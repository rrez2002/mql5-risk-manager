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

# All ordinary panel widgets and its dynamically resized bars use the same scale.
assert "InpPanelScale       = 1.35" in ea
for start, end in (("void Rect(", "int PanelFontSize("), ("void Btn(", "void Edt("),
                   ("void Edt(", "void ApplyTab(")):
    widget = ea.split(start, 1)[1].split(end, 1)[0]
    assert "PanelPixels(w)" in widget and "PanelPixels(h)" in widget
assert "PanelPixels((int)(inner*use))" in ea
assert "PanelPixels((int)(inner*duse))" in ea
assert "if(gCurTab==-1) return;" in ea
assert 'Btn("btn_min"' in ea.split("gCurTab=-1;", 1)[1].split("gCurTab=-2;", 1)[0]
assert "PlanRiskError(entry,sl,tp)" in entry
assert "PlanRiskError(entry,sl,tp)" in ea.split("void UpdateTool()", 1)[1].split("void ArmPlan", 1)[0]
print("Panel layout, restore control and shared plan validation checks passed.")

# Prices at the same screen height still render in distinct, named panel rows.
preview = ea.split("void UpdateTool()", 1)[1].split("void ArmPlan", 1)[0]
assert '{"Entry","Stop loss","Take profit"}' in ea
assert "int ry=cy+52+row*27;" in ea
for row in range(3):
    assert f'SetTxt("plan_value_{row}"' in preview
assert "OBJ_TEXT" not in ea
