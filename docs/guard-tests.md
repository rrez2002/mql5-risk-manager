# Account guard verification

On 2026-11-23 the EA compiled using the installed MetaEditor 5.0.0.6316 and its native standard library under Wine on macOS. Result: **0 errors, 0 warnings**. The source routing check passed using `python3 tests/check_guard.py` from the repository root. It checks all six submission methods, the shared stop writer, transaction-handler scope and mandatory-limit inputs. These checks do not simulate a broker.

## Windows acceptance run

All rows below are **pending demo verification**. Copy both source files to the same Experts directory, compile the EA in Build 5975 on Windows 10/11, and record the build, broker, account mode and compiler output. Use separate funded demo accounts for hedging and netting. Begin flat with complete history, no trading activity that broker day, AutoTrading enabled, and optional limits set to alert only. For independent entry tests wait 120 seconds between fills unless the row calls for faster entries. Use small fixed volumes, broker-valid tick prices and a TP, and disable automatic BE/trailing except where under test. For each row retain the Experts log, server timestamps, equity, order/deal IDs and before/after position identifiers, volume, SL and TP.

| Scenario | Action and expected observation |
|---|---|
| 1. Stop direction | Open a BUY then a SELL. Tighten each stop manually, wait for reconciliation, loosen and delete it. Expect restoration of the tighter observed stop, with unchanged TP. Try a panel stop beyond 1% and an external fill beyond 1%. Expect panel rejection and an inward, tick-aligned correction from actual entry. |
| 2. Missing protection | Submit panel plans without TP or SL. Expect rejection. Open externally without protection. Confirm immediate SL attempt. Supply TP during grace on one trade and leave another unresolved. Only the latter should require closure. |
| 3. BE and trailing | Enable both, trigger BE then trail, and invoke manual BE after the trailing stop is tighter. Check the complete sequence for monotonic stops and unchanged TP on each side. |
| 4. Aggregate risk | Size trades on two symbols so calculated loss with the candidate is just below and just above 2% of equity. Repeat with pending volume, a profitable SL and an unprotected position. Above-limit and unknown-risk panel entries must fail. Drop equity after acceptance and verify accepted volume survives. |
| 5. Concurrent submissions | Submit from two charts together, then send a manual order during a panel fill. Check that panel requests serialize and external prohibited volume is reconciled without duplicate entry. |
| 6. Exactly 6% | On a controlled demo feed start at 10,000 equity. At 9,400 expect a lock, including at equality. Repeat with a 1,000 deposit or withdrawal; the corresponding trigger equities are 10,400 and 8,400. |
| 7. Persistence | After tightening an SL and tripping the daily lock, restart the EA, then MT5. Recover equity and attempt entry. Verify the lock and the observed SL still apply. |
| 8. Midnight | Cross a quoted broker midnight with floating P/L. Record the new equity baseline and daily reset. Repeat starting late with intraday trading and no stored baseline. Expect the explicit conservative lock. |
| 9. Completed losses | Realize two net losing lifecycles including commission/swap. Split one exit in two. Only the final exit completes it. Restart during the 900-second lock; try before and after expiry. Repeat loss/profit/loss and confirm no two-loss trigger. |
| 10. Interval | Enter on symbol A, then try on B at +119 and +120 seconds from execution (allow the next whole server second for panel timing). Close during the interval. Only the early entry should be restricted. |
| 11. Symbol count | On hedging demo open two same-symbol positions with different magics. Submit a third via panel, then manually. Expect rejection or reduction of the third and preservation of the first two. |
| 12. Pending fill during lock | Place a pending order before the daily trigger. Trip the lock while price approaches it. Confirm cancellation or, if the fill wins the race, closure of prohibited new exposure. |
| 13. External scope | Place a manual or different-magic order on a symbol without an attached chart. Repeat stop deletion and interval tests with panel magic filtering enabled. |
| 14. Partial fills and closes | Use a demo venue supporting partial executions. Split one order across deals, partially close, and add during cooldown. Verify one entry order, no premature completed loss, and only prohibited residual volume closed. |
| 15. Netting | Start long, add volume, reduce, then reverse to short in a single deal. Check old volume protection, prorated reversal costs, new sell-side SL and correct residual close volume. Repeat close/re-add between timer passes. |
| 16. Rejection | Cause a freeze-level rejection or temporarily closed market. Inspect broker return codes and retry spacing. No failed request should be reported as a confirmed correction; identical unresolved intents stop after three requests. |
| 17. Permissions | Disconnect or disable AutoTrading, introduce an external violation from another terminal, then reconnect/re-enable. Verify recovery from history and actual state and rejection of unsafe panel entries. |
| 18. Multiple charts | Attach two instances on different symbols. Check one controller announcement. Trade via each chart, remove the controller and confirm takeover without duplicate correction or lost lock. |
| 19. Exits during locks | During daily, interval and completed-loss locks, use partial close, close winners/losers and full close. Broker-permitted exits must remain available. |
| 20. Panel regression | Exercise tabs, minimize, chart drag/preview, fixed and risk sizing, six order types, expiry, TP toggle, management actions, session/spread/calendar filters and existing optional locks. An absent TP must prevent submission. |

Demo-specific gaps include deterministic price control for the equality boundary, venue support for partial fills, and broker-specific rejection behavior. Record a scenario as untested if the demo venue cannot produce its prerequisite.

For the rejection and partial-fill cases, delay an acknowledgment of a netting reduction beyond ten seconds. Check the order history for a single reduction request while its outcome is outstanding. Try a manual panel partial close during that interval. After reconciliation, confirm that any remaining reduction is based on the current volume. If the broker provides neither an identifiable order ticket nor the original request comment, that position's panel reductions can remain suspended pending manual inspection.

## Panel 2.35

MetaEditor Build 6316 compiled this version with zero errors and zero warnings on 2026-11-25. The source checks passed, including shared preview/submission validation, scaled widget dimensions and the placement of the restore control. A separate portable Strategy Tester launch stopped before initialization with “tester not started because the account is not specified.” No simulated trades ran.

In the panel regression test, check the default scale (1.35) and compact scale (1.0) at standard and high DPI. Switch through all five tabs, minimize and reopen, then drag the SL beyond 1% and back. Verify the active-plan size, warnings and submission button state update together. Open Setup during the active plan and check that the displayed size matches the chart.
