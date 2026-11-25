<div align="center">

# 🛡️ MQL5 Risk Manager

**A modern, tabbed trade-management panel for MetaTrader 5.**
Risk-based position sizing · market & pending orders · on-chart SL/TP preview · account protection · trade automation.

![Platform](https://img.shields.io/badge/platform-MetaTrader%205-1f6feb?style=for-the-badge)
![Language](https://img.shields.io/badge/language-MQL5-00b894?style=for-the-badge)
![Version](https://img.shields.io/badge/version-2.38-8957e5?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-f0883e?style=for-the-badge)

**English** · [فارسی](README.fa.md)

</div>

<div align="center">
<table>
  <tr>
    <td align="center"><img src="docs/1pic.PNG" width="220" alt="Account tab"></td>
    <td align="center"><img src="docs/2pic.PNG" width="220" alt="Setup tab"></td>
    <td align="center"><img src="docs/3pic.PNG" width="220" alt="Trade tab"></td>
    <td align="center"><img src="docs/4pic.PNG" width="220" alt="Manage tab"></td>
  </tr>
  <tr>
    <td align="center"><b>ACCOUNT</b><br><sub>live stats &amp; limit bars</sub></td>
    <td align="center"><b>SETUP</b><br><sub>risk, SL, R:R &amp; sizing</sub></td>
    <td align="center"><b>TRADE</b><br><sub>market &amp; pending orders</sub></td>
    <td align="center"><b>MANAGE</b><br><sub>BE, partial &amp; close tools</sub></td>
  </tr>
</table>
</div>

---

## ✨ What is this?

**Smart Money Manager** is an Expert Advisor that does **not** trade by itself. You decide the direction and the level; the EA takes care of everything that usually blows accounts up: **position sizing, stop-loss placement, protection limits and trade management**, all from a dark, compact panel on your chart.

### Account-wide enforcement

Every chart panel checks entries before submission. One controller per broker account and terminal reconciles actual fills, pending orders and positions across symbols and magic numbers. Install both files from `Experts/` together. The guard uses the terminal's trade data and local storage.

| Area | Earlier panel behavior | Mandatory account behavior |
|---|---|---|
| Protective prices | SL sizing and optional TP | Panel entries need both prices. The maximum adverse SL distance is 1% of actual entry. BUY stops can rise and SELL stops can fall. SL repairs preserve TP. |
| Portfolio risk | Optional balance-based limit for managed trades | Proposed entry plus positions and pending volume must fit 2% of current equity, using `OrderCalcProfit` in deposit currency. Locked-in gains contribute zero. |
| Daily loss | Optional threshold using panel statistics | At 6% loss of midnight equity, adjusted for balance transfers, latch until next broker day. Cancel pending entries and attempt to unwind prohibited new volume. |
| Frequency and count | Configurable panel trade counts | Two positions per symbol and 120 seconds between account entries. Closing and partial closing remain available. |
| Losing trades | Daily streak of closing deals | Two completed losing trades trigger a 15-minute entry lock. Deal history supplies realized profit, fees, swap and commissions. A profitable completion resets the streak. |
| Missing protection | Panel-managed stops | Attempt SL repair immediately. Allow external trades 15 seconds by default to acquire valid protection. The guard never invents a TP. |

`InpProtectionGraceSeconds` accepts 0–300 seconds (larger inputs use 300). The controller chart supplies the grace setting. The existing sizing, session, spread, calendar, break-even, trailing and optional account-limit settings still apply. The optional **Hard lock** retains its original chart-scoped liquidation behavior. Select **Block new orders** to preserve existing positions when an optional limit also triggers.

**Startup and recovery.** The controller samples equity at broker midnight. With a flat account and no non-balance deals today, it can reconstruct the baseline by subtracting today's balance transfers. In other late-start cases without a saved baseline, it reports the missing observation and locks entries through the broker day. This can also happen after a quiet or disconnected midnight. A saved lock survives equity recovery and restart. The loss comparison uses equity less net transfers against 94% of starting equity.

**External orders.** Manual changes reach the broker before the EA sees them. Enforcement uses observed positions and deals. The controller keeps accepted volume and the best observed SL per position lifecycle. First installation preserves existing volume. An equity drop alone does not cause liquidation. Netting reversals start a new lifecycle, and partial exits reduce remaining exposure. Two positions per symbol normally matters only on hedging accounts.

**Execution limits.** Orders can fill during cancellation. Gaps, slippage, commissions and price changes can produce realized losses above calculated SL risk. The controller needs synchronized broker history, quotes, connectivity, trading permission and a running terminal. It cannot enforce during removal, shutdown or disabled AutoTrading, observe every intermediate SL or equity value, or coordinate independent terminals. Cash adjustments classified by the broker as balance deals are treated as transfers. Unattributed broker charges cannot be assigned to a completed position.

**Recovery actions.** Terminal global variables hold account state. Exclusive files coordinate active charts in the same terminal. Do not delete these records. MT5 can expire global variables after four weeks without access. The guard reserves panel submissions for up to 120 seconds and tracks acknowledged outstanding order tickets. If submission times out without a ticket, the guard looks for the unique request comment in live orders and broker history. Entries remain suspended while the outcome is unknown. A crash immediately before sending, or a broker that replaces the comment, can leave the account panel entry gate locked indefinitely. Existing exit controls remain available. Automated corrections allow three attempts for the same target or close volume, at least ten broker seconds apart. Inspect the Experts journal and resolve rejected corrections manually. For a missing TP, set a broker-valid target during the grace period. A close smaller than the broker's minimum tradable volume may require manual resolution.

See the [verification checklist and execution evidence](docs/guard-tests.md).

## 🚀 Features

### Execution
- **Risk-% lot sizing** from balance, stop-loss distance and the symbol's tick value (or a fixed lot override)
- **Market orders:** BUY / SELL
- **Pending orders:** Buy Limit, Sell Limit, Buy Stop, Sell Stop with configurable distance and expiry
- SL and TP are set automatically from your **SL (points)** and **R:R** values
- Free-margin check before every order

### 👁️ Live chart preview
Cycle the preview button and see **entry, SL and TP lines with lot size and money risk/reward** on the chart *before* you click.

### 🧱 Optional panel limits
| Guard | What it does |
|---|---|
| Daily loss limit | Locks trading at X % loss of the day-start balance |
| Daily profit target | Locks trading once the target is reached |
| Max drawdown | Locks at X % equity drawdown from the peak |
| Loss streak | Locks after N consecutive losing closes today |
| Max trades per day | Caps the number of trades opened today |
| Max positions | Caps open positions **+** pending orders |
| Max open risk | Caps the total SL-implied risk of everything open |

Choose how a limit reacts: **Alert only**, **Block new orders**, or **Block + close all + delete pendings**.

### 🧭 Filters
- Trading-hours window (broker server time, supports overnight windows)
- Max spread
- **News filter** using the built-in MT5 economic calendar (High or Medium + High impact, minutes before/after)

### ⚙️ Trade management
- Auto **break-even** and **trailing stop**
- **Partial close** (% of volume)
- Close all · Close winners · Close losers · Delete pendings

### 🔔 Notifications
Pop-up alerts and optional push notifications to your phone when a limit is hit.

### 🖥️ Interface
Four tabs keep the panel short: **ACCOUNT · SETUP · TRADE · MANAGE**. The header has a minimize button; protection keeps running while minimized.

## 📦 Installation

1. In MetaTrader 5 open **File → Open Data Folder**.
2. Copy `Experts/Smart_Money_Manager.mq5` and `Experts/AccountGuard.mqh` into your data folder's `MQL5/Experts/`.
3. Open **MetaEditor** (`F4`) and compile the file (`F7`).
4. Drag **Smart_Money_Manager** onto a chart and enable **Algo Trading**.
5. The news filter uses the terminal's built-in economic calendar, so no WebRequest / URL whitelist setup is needed.

> ⚠️ Always test on a **demo account** first.

## 🎛️ Usage

1. **SETUP** tab: set *Risk %*, *SL (pts)* and *R:R*. The position size and the money at risk update instantly.
2. Turn on **Preview lines** to see entry / SL / TP on the chart.
3. **TRADE** tab: press BUY, SELL or one of the four pending buttons.
4. **MANAGE** tab: break-even, partial close, close winners/losers, close all, delete pendings.
5. **ACCOUNT** tab: watch balance, equity, daily-loss and drawdown bars.

## 🔧 Inputs

<details>
<summary><b>Show all inputs</b></summary>

| Group | Input | Default | Description |
|---|---|---|---|
| Risk | `InpRiskPercent` | 1.0 | Risk per trade, % of balance |
| Risk | `InpSLPoints` | 300 | Stop loss in points |
| Risk | `InpRR` | 2.0 | Reward : Risk (zero disables preview TP and blocks submission) |
| Risk | `InpFixedLot` | 0.0 | Fixed lot (0 = auto from risk %) |
| Pending | `InpEntryDistance` | 200 | Pending distance from price (points) |
| Pending | `InpExpiryMinutes` | 0 | Pending expiry in minutes (0 = GTC) |
| Limits | `InpMaxDailyLossPct` | 3.0 | Daily loss limit, % of day-start balance |
| Limits | `InpMaxDailyProfitPct` | 0.0 | Daily profit target lock, % |
| Limits | `InpMaxDrawdownPct` | 10.0 | Max equity drawdown from peak, % |
| Limits | `InpMaxLossStreak` | 0 | Lock after N consecutive losses today |
| Limits | `InpMaxTradesPerDay` | 0 | Max trades opened per day |
| Limits | `InpMaxPositions` | 3 | Max open positions + pending orders |
| Limits | `InpMaxOpenRiskPct` | 0.0 | Max total open risk, % of balance |
| Limits | `InpLockAction` | Block | Alert only / Block new orders / Hard lock |
| Filters | `InpUseHours` | false | Enable trading-hours filter |
| Filters | `InpStartHour` / `InpEndHour` | 8 / 20 | Window in server time |
| Filters | `InpMaxSpread` | 0 | Max spread in points (0 = off) |
| Filters | `InpNewsLevel` | Off | Off / High / Medium + High |
| Filters | `InpNewsBefore` / `InpNewsAfter` | 30 / 30 | Block minutes around news |
| Management | `InpUseBE` | true | Auto break-even |
| Management | `InpBETrigger` / `InpBEOffset` | 200 / 20 | Trigger and offset (points) |
| Management | `InpUseTrail` | true | Auto trailing stop |
| Management | `InpTrailStart` / `InpTrailDist` / `InpTrailStep` | 300 / 150 / 20 | Trailing parameters (points) |
| Management | `InpPartialPct` | 50 | Partial close, % of volume |
| Notify | `InpPopupAlerts` / `InpPushAlerts` | true / false | Alerts |
| General | `InpMagic` | 20260512 | Magic number |
| General | `InpSlippage` | 20 | Max slippage (points) |
| General | `InpManageAllMagic` | false | Manage trades of all magics on this symbol |
| General | `InpPanelScale` | 1.35 | Panel scale. Use 1.0 for compact charts. Supported range 0.85–2.0. |
| General | `InpPanelX` / `InpPanelY` | 15 / 25 | Panel position |

Optional settings cannot relax the mandatory guard.

</details>

## ⚠️ Notes & limitations

- The panel status line reports active daily and completed-loss locks. The statistics and bars continue to show the original panel metrics.
- For optional management actions, by default only trades with this EA's **magic number** are managed. Enable `InpManageAllMagic` to manage all trades on the symbol.
- The drawdown peak is tracked from when the EA starts; it is saved in terminal global variables.
- "Daily" statistics use the broker's server-day (midnight server time).
- The news filter needs the terminal's economic calendar to be available on your broker/account.
- Panel text is in English (MT5 does not render right-to-left text reliably on charts).

## 🛠️ Roadmap

- [ ] Per-prop-firm presets (FTMO, The5ers…)
- [ ] Weekly / monthly limits
- [ ] Partial take-profit levels (TP1 / TP2 / TP3)
- [ ] Light theme
- [ ] Hotkeys

Contributions and ideas are welcome: open an issue or a pull request.

## 📜 Disclaimer

Trading leveraged products carries a high level of risk and may not be suitable for everyone. This software is a risk-management **utility**, not investment advice and not a profit guarantee. Use it at your own risk; the authors are not liable for any losses.

## 📄 License

[MIT](LICENSE)
