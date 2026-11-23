// Account-wide controller. File sharing is intentionally disabled for the owner handle.
input uint InpProtectionGraceSeconds=15; // Time allowed to repair new exposure

struct GuardLeg
  {
   long id,epoch,order,latest;
   double accepted,grandfathered;
   double volume,net,prohibited;
  };
GuardLeg legs[];
string guardPrefix;
int owner=INVALID_HANDLE;
bool historyDirty=true,guardReady=false,dayActivity=false;
datetime historyDay=0,lastEntry=0,lossUntil=0,dayLock=0;
long lastOrder=0,lastEntryMsc=0;
double cashFlow=0;
int historyCount=-1;
CTrade corrective;

string GuardKey(string suffix) { return guardPrefix+suffix; }
double Stored(string key) { return GlobalVariableCheck(key)?GlobalVariableGet(key):0; }
bool Save(string key,double value)
  {
   if(GlobalVariableCheck(key) && GlobalVariableGet(key)==value) return true;
   if(GlobalVariableSet(key,value)==0) { guardReady=false; Print("Guard storage failed: ",key); return false; }
   GlobalVariablesFlush();
   return true;
  }
void GuardInit()
  {
   string server=AccountInfoString(ACCOUNT_SERVER);
   uint hash=2166136261;
   for(int i=0;i<StringLen(server);i++) hash=(hash^StringGetCharacter(server,i))*16777619;
   guardPrefix=StringFormat("S3.%u.%I64d.",hash,AccountInfoInteger(ACCOUNT_LOGIN));
  }
// All chart instances serialize panel submissions and controller corrections.
class GuardAccess
  {
private:
   int handle;
public:
   GuardAccess() { handle=FileOpen(GuardKey("operation"),FILE_READ|FILE_WRITE|FILE_BIN); }
   ~GuardAccess() { if(handle!=INVALID_HANDLE) FileClose(handle); }
   bool Acquired() { return handle!=INVALID_HANDLE; }
  };
bool Allowed()
  {
   return TerminalInfoInteger(TERMINAL_CONNECTED) && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
       && MQLInfoInteger(MQL_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)
       && AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
  }
bool Done(CTrade &client,bool sent)
  {
   uint rc=client.ResultRetcode();
   if(sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL)) return true;
   Print("Trade request: ",rc," ",client.ResultRetcodeDescription());
   return false;
  }
int FindLeg(long id)
  {
   for(int i=ArraySize(legs)-1;i>=0;i--) if(legs[i].id==id) return i;
   return -1;
  }
bool Replay(datetime now,datetime day)
  {
   if(!HistorySelect(day,now)) return false;
   int count=HistoryDealsTotal();
   if(!historyDirty && day==historyDay && count==historyCount) return true;
   historyDirty=true;
   if(!HistorySelect(0,now)) return false;
   ArrayFree(legs);
   lastEntry=0; lastEntryMsc=0; lastOrder=0; lossUntil=0; cashFlow=0; dayActivity=false;
   int streak=0;
   for(int j=0;j<HistoryDealsTotal();j++)
     {
      ulong t=HistoryDealGetTicket(j);
      if(!t) return false;
      datetime when=(datetime)HistoryDealGetInteger(t,DEAL_TIME);
      long type=HistoryDealGetInteger(t,DEAL_TYPE);
      double profit=HistoryDealGetDouble(t,DEAL_PROFIT);
      if(type!=DEAL_TYPE_BALANCE && when>=day) dayActivity=true;
      if(type==DEAL_TYPE_BALANCE && when>=day) cashFlow+=profit;
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      long id=HistoryDealGetInteger(t,DEAL_POSITION_ID),order=HistoryDealGetInteger(t,DEAL_ORDER);
      int i=FindLeg(id);
      if(i<0)
        {
         i=ArraySize(legs);
         if(ArrayResize(legs,i+1,64)!=i+1) return false;
         ZeroMemory(legs[i]); legs[i].id=id;
        }
      double old=legs[i].volume,qty=HistoryDealGetDouble(t,DEAL_VOLUME);
      long side=HistoryDealGetInteger(t,DEAL_ENTRY);
      if(old==0 && side!=DEAL_ENTRY_IN) return false;
      double delta=(type==DEAL_TYPE_BUY?qty:-qty);
      double closed=old*delta<0?MathMin(MathAbs(old),qty):0;
      double added=NormalizeDouble(qty-closed,8);
      double fees=HistoryDealGetDouble(t,DEAL_FEE)+HistoryDealGetDouble(t,DEAL_COMMISSION);
      if(qty<=0) return false;
      legs[i].net+=profit+HistoryDealGetDouble(t,DEAL_SWAP)+fees*closed/qty;
      legs[i].prohibited=MathMax(0,legs[i].prohibited-closed);
      if(closed>0 && closed>=MathAbs(old)-1e-9)
        {
         if(legs[i].net<0 && ++streak>=2) lossUntil=when+900;
         if(legs[i].net>0) streak=0;
         legs[i].net=0;
        }
      if(added>0)
        {
         if(MathAbs(old)<=closed+1e-9)
           { legs[i].epoch=(long)t; legs[i].accepted=0; legs[i].grandfathered=0; }
         datetime dealDay=when-when%86400;
         datetime lockedAt=(datetime)Stored(GuardKey("D"+IntegerToString(dealDay)));
         long whenMsc=HistoryDealGetInteger(t,DEAL_TIME_MSC);
         bool barred=(order!=legs[i].order && order!=lastOrder && whenMsc-lastEntryMsc<120000) || when<lossUntil
                   || (lockedAt>0 && when>=lockedAt);
         if(barred || (order==legs[i].order && legs[i].prohibited>0)) legs[i].prohibited+=added;
         legs[i].order=order;
         legs[i].net+=fees*added/qty;
         lastEntry=when; lastEntryMsc=whenMsc; lastOrder=order;
        }
      legs[i].volume=NormalizeDouble(old+delta,8);
      legs[i].latest=(long)t;
      string checkpoint=GuardKey(IntegerToString((long)t)+"v");
      legs[i].accepted=MathMin(legs[i].accepted,MathAbs(legs[i].volume));
      if(GlobalVariableCheck(checkpoint)) legs[i].accepted=Stored(checkpoint);
      legs[i].grandfathered=MathMin(MathAbs(legs[i].volume),MathMax(legs[i].grandfathered,Stored(checkpoint+"f")));
      legs[i].prohibited=MathMax(legs[i].prohibited,Stored(GuardKey(IntegerToString((long)t)+"x")));
      legs[i].prohibited=MathMin(legs[i].prohibited,MathAbs(legs[i].volume)-legs[i].accepted);
      if(legs[i].volume==0)
        {
         int end=ArraySize(legs)-1;
         if(i!=end) legs[i]=legs[end];
         ArrayResize(legs,end);
        }
     }
   historyDirty=false; historyCount=count; historyDay=day;
   return true;
  }
bool GuardRefresh()
  {
   guardReady=false;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   datetime now=TimeTradeServer(),day=now-now%86400;
   if(now<=0) return false;
   string base=GuardKey("B"+IntegerToString(day)),lock=GuardKey("D"+IntegerToString(day));
   dayLock=(datetime)Stored(lock);
   if(!Replay(now,day)) return false;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(!MathIsValidNumber(equity)) return false;
   if(!GlobalVariableCheck(base))
     {
      bool flatSinceMidnight=!dayActivity && PositionsTotal()==0 && ArraySize(legs)==0;
      if((now!=day || TimeCurrent()!=day) && !flatSinceMidnight)
        {
         if(!dayLock && !Save(lock,now)) return false;
         dayLock=(datetime)Stored(lock);
         Print("Midnight equity unavailable. Entries locked for the broker day.");
        }
      if(!Save(base,equity-cashFlow)) return false;
     }
   if(!dayLock && equity-cashFlow<=Stored(base)*0.94)
     {
      if(!Save(lock,now)) return false;
      dayLock=now; historyDirty=true;
      if(!Replay(now,day)) return false;
      Print("Account daily equity loss lock activated.");
     }
   guardReady=true; return true;
  }
double Grid(string s,double price,bool up)
  {
   double tick=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) return 0;
   double n=up?MathCeil(price/tick-1e-8):MathFloor(price/tick+1e-8);
   return NormalizeDouble(n*tick,(int)SymbolInfoInteger(s,SYMBOL_DIGITS));
  }
bool Loss(string s,bool buy,double v,double entry,double sl,double &sum)
  {
   if(v<=0 || sl<=0 || entry<=0 || (buy?entry-sl:sl-entry)>entry*0.01+1e-10) return false;
   double pnl;
   if(!OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,s,v,entry,sl,pnl) || !MathIsValidNumber(pnl)) return false;
   sum+=MathMax(0,-pnl); return true;
  }
bool Portfolio(double &sum,long through=LONG_MAX)
  {
   for(int i=0;i<PositionsTotal();i++)
     {
      if(!PositionGetTicket(i)) return false;
      int leg=FindLeg(PositionGetInteger(POSITION_IDENTIFIER));
      if(leg<0) return false;
      double vol=PositionGetDouble(POSITION_VOLUME);
      if(MathAbs(MathAbs(legs[leg].volume)-vol)>1e-8) return false;
      if(legs[leg].latest>through) vol=MathMin(vol,legs[leg].accepted);
      if(vol<=0) continue;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double sl=PositionGetDouble(POSITION_SL),best=Stored(LegKey(leg)+"s");
      if(best>0 && (buy?sl<best:sl>best)) return false;
      if(!Loss(PositionGetString(POSITION_SYMBOL),buy,vol,PositionGetDouble(POSITION_PRICE_OPEN),sl,sum)) return false;
     }
   for(int i=0;i<OrdersTotal();i++)
     {
      if(!OrderGetTicket(i)) return false;
      long type=OrderGetInteger(ORDER_TYPE);
      bool buy=type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT;
      if(type<ORDER_TYPE_BUY_LIMIT || type>ORDER_TYPE_SELL_STOP_LIMIT) return false;
      double entry=OrderGetDouble(ORDER_PRICE_OPEN),limit=OrderGetDouble(ORDER_PRICE_STOPLIMIT);
      if(limit>0) entry=buy?MathMax(entry,limit):MathMin(entry,limit);
      if((buy?OrderGetDouble(ORDER_SL)>=entry:OrderGetDouble(ORDER_SL)<=entry)) return false;
      if(!Loss(OrderGetString(ORDER_SYMBOL),buy,OrderGetDouble(ORDER_VOLUME_CURRENT),entry,OrderGetDouble(ORDER_SL),sum)) return false;
     }
   return sum<=AccountInfoDouble(ACCOUNT_EQUITY)*0.02;
  }
int EarlierPositions(string s,long opened,ulong ticket)
  {
   int n=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong t=PositionGetTicket(i);
      long at=PositionGetInteger(POSITION_TIME_MSC);
      if(PositionGetString(POSITION_SYMBOL)==s && (at<opened || (at==opened && t<ticket))) n++;
     }
   return n;
  }
// An acknowledged order can remain at the exchange after the local request returns.
bool RequestOutstanding(string prefix)
  {
   long high=(long)Stored(prefix+"orderHi"),low=(long)Stored(prefix+"orderLo");
   ulong ticket=((ulong)high<<32)|(ulong)low;
   long token=(long)Stored(prefix+"sending");
   if(ticket==0 && token!=0)
     {
      string tag="SMM#"+IntegerToString(token);
      for(int i=OrdersTotal()-1;i>=0 && ticket==0;i--)
        {
         ulong t=OrderGetTicket(i);
         if(t && OrderGetString(ORDER_COMMENT)==tag) ticket=t;
        }
      if(ticket==0)
        {
         if(!HistorySelect((datetime)(token/1000)-120,TimeTradeServer())) return true;
         for(int i=HistoryOrdersTotal()-1;i>=0;i--)
           {
            ulong t=HistoryOrderGetTicket(i);
            if(t && HistoryOrderGetString(t,ORDER_COMMENT)==tag) { ticket=t; break; }
           }
        }
      if(ticket==0) return true;
     }
   if(ticket==0) return false;
   if(OrderSelect(ticket))
     {
      if(OrderGetInteger(ORDER_TYPE)<=ORDER_TYPE_SELL) return true;
      // A visible pending order is now included in Portfolio.
     }
   else if(!HistoryOrderSelect(ticket)) return true;
   else
     {
      long state=HistoryOrderGetInteger(ticket,ORDER_STATE);
      if(state!=ORDER_STATE_FILLED && state!=ORDER_STATE_CANCELED && state!=ORDER_STATE_REJECTED && state!=ORDER_STATE_EXPIRED)
         return true;
     }
   return !Save(prefix+"sending",0) || !Save(prefix+"orderHi",0) || !Save(prefix+"orderLo",0);
  }
bool GuardEntry(bool buy,bool market,double volume,double entry,double sl,double tp)
  {

   string why="";
   if(!Allowed() || !GuardRefresh()) why="Guard unavailable";
   else if(!GlobalVariableCheck(GuardKey("installed"))) why="Controller initializing";
   else if(dayLock) why="Daily equity lock";
   else if(TimeCurrent()<lossUntil) why="Completed-loss lock";
   else if(RequestOutstanding(guardPrefix) || (long)TimeCurrent()*1000-lastEntryMsc<120000 || Stored(GuardKey("reserved"))>TimeCurrent()) why="Entry interval or request pending";
   else if(EarlierPositions(_Symbol,LONG_MAX,0)>=2) why="Symbol position limit";
   long mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(mode!=SYMBOL_TRADE_MODE_FULL && mode!=(buy?SYMBOL_TRADE_MODE_LONGONLY:SYMBOL_TRADE_MODE_SHORTONLY))
      why="Symbol trading restricted";
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && PositionSelect(_Symbol))
     {
      double old=PositionGetDouble(POSITION_SL);
      if((PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)==buy && old>0 && (buy?sl<old:sl>old))
         why="Netting order would loosen existing stop";
     }
   double sum=0;
   if(why=="" && (!Loss(_Symbol,buy,volume,entry,sl,sum) || !Portfolio(sum))) why="Account risk exceeds limit or is unknown";
   double gap=GuardGap(_Symbol);
   MqlTick q;
   if(why=="" && (!SymbolInfoTick(_Symbol,q) || tp<=0 || sl<=0 ||
      MathAbs(Grid(_Symbol,entry,true)-entry)>_Point*0.01 ||
      MathAbs(Grid(_Symbol,tp,true)-tp)>_Point*0.01 || MathAbs(Grid(_Symbol,sl,true)-sl)>_Point*0.01 ||
      (buy?(market?q.bid:entry)-sl:sl-(market?q.ask:entry))<gap ||
      (buy?tp-(market?q.bid:entry):(market?q.ask:entry)-tp)<gap)) why="Invalid protective prices";
   if(why!="") { SetStatus(why,C_WARN); return false; }
   long token=(long)MathMax((double)((long)TimeCurrent()*1000),Stored(GuardKey("sequence"))+1);
   return Save(GuardKey("reserved"),TimeCurrent()+120) && Save(GuardKey("sequence"),(double)token)
       && Save(GuardKey("sending"),(double)token);
  }
double GuardGap(string s)
  {
   return SymbolInfoDouble(s,SYMBOL_POINT)*MathMax(SymbolInfoInteger(s,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(s,SYMBOL_TRADE_FREEZE_LEVEL));
  }
string LegKey(int i) { return GuardKey(IntegerToString(legs[i].epoch)); }
bool RetrySlot(string key,double intent)
  {
   double last=Stored(key);
   if(last>TimeCurrent()) return false;
   double attempts=Stored(key+"n");
   if(Stored(key+"i")!=intent) attempts=0;
   if(attempts>=3) return false;
   if(attempts==2) Print("Final automatic attempt for ",key);
   return Save(key+"i",intent) && Save(key+"n",attempts+1) && Save(key,TimeCurrent()+10);
  }
bool GuardStop(ulong t,double candidate)
  {
   if(!guardReady || !Allowed() || !PositionSelectByTicket(t)) return false;
   int i=FindLeg(PositionGetInteger(POSITION_IDENTIFIER));
   if(i<0) return false;
   string s=PositionGetString(POSITION_SYMBOL),key=LegKey(i);
   bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
   double sl=PositionGetDouble(POSITION_SL),entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double limit=Grid(s,entry*(buy?0.99:1.01),buy),saved=Stored(key+"s");
   double target=Grid(s,candidate,buy);
   if(limit<=0 || target<=0 || (buy?target<limit:target>limit) ||
      (saved>0 && (buy?target<saved:target>saved)) || (sl>0 && (buy?target<=sl:target>=sl))) return false;
   MqlTick q;
   if(SymbolInfoInteger(s,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED || !SymbolInfoTick(s,q) || (buy?q.bid-target:target-q.ask)<=GuardGap(s) || !RetrySlot(key+"m",target)) return false;
   bool ok=Done(corrective,corrective.PositionModify(t,target,PositionGetDouble(POSITION_TP)));
   if(ok && PositionSelectByTicket(t) && PositionGetDouble(POSITION_SL)==target)
     { Save(key+"s",target); Save(key+"mn",0); }
   return ok;
  }
bool Reduce(ulong t,double amount,string key,long observedUpdate,bool automatic)
  {
   if(!Allowed() || !PositionSelectByTicket(t) || PositionGetInteger(POSITION_TIME_UPDATE_MSC)!=observedUpdate)
      return false;
   string s=PositionGetString(POSITION_SYMBOL);
   double vol=PositionGetDouble(POSITION_VOLUME),step=SymbolInfoDouble(s,SYMBOL_VOLUME_STEP);
   string requestKey=GuardKey(IntegerToString(PositionGetInteger(POSITION_IDENTIFIER))+"r");
   if(step<=0 || RequestOutstanding(requestKey)) return false;
   double maximum=SymbolInfoDouble(s,SYMBOL_VOLUME_MAX);
   double part=NormalizeDouble(MathFloor((MathMin(maximum,MathMin(amount,vol))+1e-9)/step)*step,8);
   if(SymbolInfoInteger(s,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED || part<=0 || (part<vol &&
      (part<SymbolInfoDouble(s,SYMBOL_VOLUME_MIN) || vol-part+1e-9<SymbolInfoDouble(s,SYMBOL_VOLUME_MIN)))) return false;
   MqlTradeRequest req={};
   MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.position=t; req.symbol=s; req.volume=part;
   req.type=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   req.price=SymbolInfoDouble(s,req.type==ORDER_TYPE_BUY?SYMBOL_ASK:SYMBOL_BID);
   req.deviation=InpSlippage; req.magic=InpMagic;
   long fill=SymbolInfoInteger(s,SYMBOL_FILLING_MODE);
   req.type_filling=(fill&SYMBOL_FILLING_IOC)!=0?ORDER_FILLING_IOC:((fill&SYMBOL_FILLING_FOK)!=0?ORDER_FILLING_FOK:ORDER_FILLING_RETURN);
   if(automatic && !RetrySlot(key+"c",vol)) return false;
   MqlTradeCheckResult check={};
   if(!OrderCheck(req,check)) { Print("Reduction check: ",check.comment); return false; }
   long token=(long)MathMax((double)((long)TimeCurrent()*1000),Stored(GuardKey("sequence"))+1);
   req.comment="SMM#"+IntegerToString(token);
   if(!PositionSelectByTicket(t) || PositionGetInteger(POSITION_TIME_UPDATE_MSC)!=observedUpdate ||
      PositionGetDouble(POSITION_VOLUME)!=vol || !Save(GuardKey("sequence"),(double)token) ||
      !Save(requestKey+"sending",(double)token)) return false;
   bool sent=OrderSend(req,res);
   if(res.order>0)
     {
      Save(requestKey+"orderHi",(double)(res.order>>32));
      Save(requestKey+"orderLo",(double)(res.order&0xFFFFFFFF));
     }
   if(res.retcode==TRADE_RETCODE_PLACED || res.retcode==TRADE_RETCODE_TIMEOUT ||
      res.retcode==TRADE_RETCODE_CONNECTION || res.retcode==TRADE_RETCODE_ERROR || res.retcode==0)
     {
      Print("Reduction outcome pending for ",t,". Verify broker order ",res.order," before further reduction.");
      return false;
     }
   if(!res.order && res.retcode!=TRADE_RETCODE_DONE_PARTIAL) Save(requestKey+"sending",0);
   if(sent && (res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_DONE_PARTIAL)) return true;
   Print("Reduction result: ",res.retcode," ",res.comment); return false;
  }
void GuardPosition(ulong t,bool first)
  {
   if(!PositionSelectByTicket(t)) return;
   int i=FindLeg(PositionGetInteger(POSITION_IDENTIFIER));
   double vol=PositionGetDouble(POSITION_VOLUME);
   bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
   if(i<0 || MathAbs(legs[i].volume-(buy?vol:-vol))>1e-8) { historyDirty=true; guardReady=false; return; }
   string key=LegKey(i),s=PositionGetString(POSITION_SYMBOL);
   double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   long opened=PositionGetInteger(POSITION_TIME_MSC),updated=PositionGetInteger(POSITION_TIME_UPDATE_MSC);
   double bound=Grid(s,entry*(buy?0.99:1.01),buy),best=Stored(key+"s");
   if(bound<=0) { guardReady=false; return; }
   double target=best==0?bound:(buy?MathMax(bound,best):MathMin(bound,best));
   bool protectedSL=sl>0 && (buy?sl>=target:sl<=target);
   if(protectedSL) { if(!Save(key+"s",sl)) return; }
   else if(GuardStop(t,target))
     {
      if(!PositionSelectByTicket(t) || PositionGetDouble(POSITION_VOLUME)!=vol ||
         PositionGetDouble(POSITION_PRICE_OPEN)!=entry) return;
      sl=PositionGetDouble(POSITION_SL); tp=PositionGetDouble(POSITION_TP);
      protectedSL=sl>0 && (buy?sl>=target:sl<=target);
     }
   string checkpoint=GuardKey(IntegerToString(legs[i].latest));
   double accepted=MathMin(vol,legs[i].accepted);
   if(first)
     {
      accepted=vol; legs[i].grandfathered=vol;
      if(!Save(checkpoint+"vf",vol)) return;
     }
   double extra=NormalizeDouble(vol-accepted,8);
   double grace=Stored(key+"g");
   bool missing=!protectedSL || tp<=0;
   if(missing && !grace)
     {
      grace=(double)TimeCurrent();
      double atRisk=extra>0?extra:MathMax(0,vol-legs[i].grandfathered);
      if(!Save(key+"floor",vol-atRisk) || !Save(key+"g",grace)) return;
      Print("Protection grace started for position ",t);
     }
   if(!missing && grace && !Save(key+"g",0)) return;
   double banned=MathMin(extra,legs[i].prohibited);
   if(extra>0)
     {
      if(EarlierPositions(s,opened,t)>=2) banned=extra;
      double risk=0;
      if(protectedSL && !Portfolio(risk,legs[i].latest)) banned=extra;
     }
   if(missing && TimeCurrent()>=grace+MathMin(InpProtectionGraceSeconds,300))
      banned=MathMax(banned,MathMax(extra,vol-Stored(key+"floor")));
   if(banned>0)
     {
      accepted=MathMin(accepted,vol-banned);
      legs[i].accepted=accepted;
      if(!Save(checkpoint+"x",banned) || !Save(checkpoint+"v",accepted)) return;
      legs[i].prohibited=MathMax(legs[i].prohibited,banned);
      Reduce(t,banned,key,updated,true);
     }
   else if(!missing || first)
     {
      if(Save(checkpoint+"v",vol)) { legs[i].accepted=vol; legs[i].prohibited=0; }
     }
  }
void GuardCycle()
  {
   if(owner==INVALID_HANDLE)
     {
      owner=FileOpen(GuardKey("owner"),FILE_READ|FILE_WRITE|FILE_BIN);
      if(owner==INVALID_HANDLE) return;
      historyDirty=true;
      corrective.SetExpertMagicNumber(InpMagic); corrective.SetDeviationInPoints(InpSlippage);
      Print("Account enforcement controller active on ",_Symbol);
     }
   GuardAccess access;
   if(!access.Acquired() || !GuardRefresh()) return;
   bool first=!GlobalVariableCheck(GuardKey("installed"));
   for(int j=PositionsTotal()-1;j>=0;j--) GuardPosition(PositionGetTicket(j),first);
   if(first && guardReady) Save(GuardKey("installed"),1);
   if(!dayLock || !Allowed()) return;
   for(int j=OrdersTotal()-1;j>=0;j--)
     {
      ulong t=OrderGetTicket(j);
      if(t && OrderGetInteger(ORDER_TYPE)>=ORDER_TYPE_BUY_LIMIT && OrderGetInteger(ORDER_TYPE)<=ORDER_TYPE_SELL_STOP_LIMIT &&
         RetrySlot(GuardKey(IntegerToString((long)t)+"d"),1))
         Done(corrective,corrective.OrderDelete(t));
     }
  }
