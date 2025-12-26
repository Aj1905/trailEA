//+------------------------------------------------------------------+
//|                                                    trailEA.mq4   |
//|                        MT4用トレーリングストップEA                |
//+------------------------------------------------------------------+
#property copyright "TrailEA"
#property version   "1.00"
#property strict

// 設定ファイルのパス
string configFile = "trailEA.ini";

// 設定パラメータ
double allowableLossRate = 0.01;      // 許容損失率
int breakEvenTriggerPips = 20;        // 建値に戻すトリガーpip数
int trailIntervalPips = 10;           // トレール間隔pip数

// 内部変数
datetime lastCheckTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // 設定ファイルを読み込む
   if(!LoadConfig())
   {
      Print("設定ファイルの読み込みに失敗しました: ", configFile);
      return(INIT_FAILED);
   }
   
   Print("TrailEA初期化完了");
   Print("許容損失率: ", allowableLossRate);
   Print("建値トリガー: ", breakEvenTriggerPips, " pips");
   Print("トレール間隔: ", trailIntervalPips, " pips");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("TrailEA終了");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1秒に1回チェック
   if(TimeCurrent() - lastCheckTime < 1)
      return;
   lastCheckTime = TimeCurrent();
   
   // 全ポジションをチェック
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == 0) // 全注文を対象（必要に応じてMagicNumberでフィルタ）
         {
            ProcessPosition();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ポジション処理                                                    |
//+------------------------------------------------------------------+
void ProcessPosition()
{
   string symbol = OrderSymbol();
   int ticket = OrderTicket();
   double openPrice = OrderOpenPrice();
   double currentSL = OrderStopLoss();
   double currentTP = OrderTakeProfit();
   int orderType = OrderType();
   
   double currentPrice = 0;
   if(orderType == OP_BUY)
      currentPrice = Bid;
   else if(orderType == OP_SELL)
      currentPrice = Ask;
   else
      return; // 未決済注文はスキップ
   
   double point = Point;
   int digits = Digits;
   double pipValue = GetPipValue(symbol, point, digits);
   
   double profit = OrderProfit();
   double profitPips = GetProfitInPips(symbol, openPrice, currentPrice, orderType, pipValue);
   
   // 新規注文の場合、初期StopLossを設定
   if(currentSL == 0.0)
   {
      double initialSL = CalculateInitialStopLoss(symbol, openPrice, orderType, point);
      if(initialSL > 0)
      {
         ModifyStopLoss(symbol, ticket, initialSL, currentTP);
         Print("初期StopLoss設定: ", initialSL, " (", symbol, ")");
      }
      return;
   }
   
   // 建値に戻す処理
   if(profitPips >= breakEvenTriggerPips && currentSL < openPrice && orderType == OP_BUY)
   {
      ModifyStopLoss(symbol, ticket, openPrice, currentTP);
      Print("StopLossを建値に設定: ", openPrice, " (", symbol, ")");
      return;
   }
   
   if(profitPips >= breakEvenTriggerPips && (currentSL > openPrice || currentSL == 0) && orderType == OP_SELL)
   {
      ModifyStopLoss(symbol, ticket, openPrice, currentTP);
      Print("StopLossを建値に設定: ", openPrice, " (", symbol, ")");
      return;
   }
   
   // トレーリングストップ処理
   if(profitPips > breakEvenTriggerPips)
   {
      double newSL = CalculateTrailingStopLoss(symbol, openPrice, currentPrice, currentSL, orderType, profitPips, pipValue, point);
      
      if(newSL > 0 && ((orderType == OP_BUY && newSL > currentSL) || 
                       (orderType == OP_SELL && (currentSL == 0 || newSL < currentSL))))
      {
         ModifyStopLoss(symbol, ticket, newSL, currentTP);
         Print("トレーリングStopLoss更新: ", newSL, " (", symbol, ", 含み益: ", profitPips, " pips)");
      }
   }
}

//+------------------------------------------------------------------+
//| 初期StopLossを計算                                                |
//+------------------------------------------------------------------+
double CalculateInitialStopLoss(string symbol, double openPrice, int orderType, double point)
{
   double balance = AccountBalance();
   double lotSize = OrderLots();
   
   // 許容損失額を計算
   double allowableLoss = balance * allowableLossRate;
   
   // StopLoss幅を計算
   double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
   double tickSize = MarketInfo(symbol, MODE_TICKSIZE);
   
   // 許容損失額から逆算してStopLoss幅を求める
   double slDistance = 0;
   if(lotSize > 0 && tickValue > 0 && tickSize > 0)
   {
      // 損失額 = (StopLoss幅 / tickSize) * tickValue * lotSize
      // StopLoss幅 = (損失額 / (tickValue * lotSize)) * tickSize
      slDistance = (allowableLoss / (tickValue * lotSize)) * tickSize;
      
      // 最小限のStopLoss幅を確保（証拠金維持率を考慮）
      double minSL = GetMinimumStopLoss(symbol, point);
      if(slDistance < minSL)
         slDistance = minSL;
   }
   
   if(orderType == OP_BUY)
      return NormalizeDouble(openPrice - slDistance, Digits);
   else
      return NormalizeDouble(openPrice + slDistance, Digits);
}

//+------------------------------------------------------------------+
//| 最小StopLoss幅を取得（証拠金維持率を考慮）                        |
//+------------------------------------------------------------------+
double GetMinimumStopLoss(string symbol, double point)
{
   // 証拠金維持率から最小限のStopLoss幅を計算
   double marginLevel = AccountMarginLevel();
   double margin = AccountMargin();
   double equity = AccountEquity();
   
   // デフォルトで50pipsを最小値とする（証拠金維持率が低い場合は調整）
   double minPips = 50.0;
   
   if(marginLevel > 0)
   {
      // 証拠金維持率が低い場合は、より大きなStopLoss幅を設定
      if(marginLevel < 200.0)  // 200%未満の場合
         minPips = 100.0;
      else if(marginLevel < 300.0)  // 300%未満の場合
         minPips = 75.0;
   }
   
   int digits = Digits;
   double pipValue = GetPipValue(symbol, point, digits);
   
   return minPips * pipValue;
}

//+------------------------------------------------------------------+
//| トレーリングStopLossを計算                                        |
//+------------------------------------------------------------------+
double CalculateTrailingStopLoss(string symbol, double openPrice, double currentPrice, 
                                 double currentSL, int orderType, 
                                 double profitPips, double pipValue, double point)
{
   // 建値からの利益がトレール間隔の倍数になるようにStopLossを調整
   int intervals = (int)((profitPips - breakEvenTriggerPips) / trailIntervalPips);
   double targetProfitPips = breakEvenTriggerPips + (intervals * trailIntervalPips);
   
   double slDistancePips = targetProfitPips - trailIntervalPips;
   double slDistance = slDistancePips * pipValue;
   
   double newSL = 0;
   if(orderType == OP_BUY)
   {
      newSL = NormalizeDouble(currentPrice - slDistance, Digits);
      // 現在のStopLossより低くならないように
      if(newSL <= currentSL && currentSL > 0)
         newSL = currentSL;
      // 建値より低くならないように
      if(newSL < openPrice)
         newSL = openPrice;
   }
   else
   {
      newSL = NormalizeDouble(currentPrice + slDistance, Digits);
      // 現在のStopLossより高くならないように
      if(newSL >= currentSL && currentSL > 0)
         newSL = currentSL;
      // 建値より高くならないように
      if(newSL > openPrice)
         newSL = openPrice;
   }
   
   return newSL;
}

//+------------------------------------------------------------------+
//| StopLossを修正                                                    |
//+------------------------------------------------------------------+
void ModifyStopLoss(string symbol, int ticket, double sl, double tp)
{
   double minStopLevel = MarketInfo(symbol, MODE_STOPLEVEL) * Point;
   double currentPrice = 0;
   
   if(OrderSelect(ticket, SELECT_BY_TICKET))
   {
      int orderType = OrderType();
      if(orderType == OP_BUY)
         currentPrice = Bid;
      else if(orderType == OP_SELL)
         currentPrice = Ask;
      else
         return;
      
      // 最小StopLevelをチェック
      if(orderType == OP_BUY)
      {
         if(currentPrice - sl < minStopLevel && minStopLevel > 0)
            sl = NormalizeDouble(currentPrice - minStopLevel, Digits);
      }
      else
      {
         if(sl - currentPrice < minStopLevel && minStopLevel > 0)
            sl = NormalizeDouble(currentPrice + minStopLevel, Digits);
      }
      
      if(!OrderModify(ticket, OrderOpenPrice(), sl, tp, 0, clrNONE))
      {
         Print("StopLoss修正失敗: ", GetLastError(), " Ticket: ", ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| 含み益をpipsで取得                                                |
//+------------------------------------------------------------------+
double GetProfitInPips(string symbol, double openPrice, double currentPrice, 
                       int orderType, double pipValue)
{
   double priceDiff = 0;
   if(orderType == OP_BUY)
      priceDiff = currentPrice - openPrice;
   else
      priceDiff = openPrice - currentPrice;
   
   if(pipValue > 0)
      return priceDiff / pipValue;
   return 0;
}

//+------------------------------------------------------------------+
//| Pip値を取得                                                       |
//+------------------------------------------------------------------+
double GetPipValue(string symbol, double point, int digits)
{
   // 4桁通貨ペア（USD/JPY以外）の場合
   if(digits == 4 || digits == 5)
   {
      if(digits == 5)
         return point * 10;  // 5桁の場合は0.00001 = 0.1 pip
      else
         return point * 10;  // 4桁の場合は0.0001 = 1 pip
   }
   // 2桁通貨ペア（USD/JPYなど）の場合
   else if(digits == 2 || digits == 3)
   {
      if(digits == 3)
         return point * 10;  // 3桁の場合は0.001 = 0.1 pip
      else
         return point * 10;  // 2桁の場合は0.01 = 1 pip
   }
   
   return point * 10;  // デフォルト
}

//+------------------------------------------------------------------+
//| 設定ファイルを読み込む                                            |
//+------------------------------------------------------------------+
bool LoadConfig()
{
   int fileHandle = FileOpen(configFile, FILE_READ|FILE_TXT);
   if(fileHandle == INVALID_HANDLE)
   {
      Print("設定ファイルが見つかりません: ", configFile);
      return false;
   }
   
   while(!FileIsEnding(fileHandle))
   {
      string line = FileReadString(fileHandle);
      line = StringTrimLeft(StringTrimRight(line));
      
      // コメント行をスキップ
      if(StringFind(line, ";") == 0 || StringLen(line) == 0)
         continue;
      
      // セクションをスキップ
      if(StringFind(line, "[") == 0)
         continue;
      
      // パラメータを解析
      int eqPos = StringFind(line, "=");
      if(eqPos > 0)
      {
         string paramName = StringSubstr(line, 0, eqPos);
         string paramValue = StringSubstr(line, eqPos + 1);
         
         paramName = StringTrimLeft(StringTrimRight(paramName));
         paramValue = StringTrimLeft(StringTrimRight(paramValue));
         
         if(paramName == "AllowableLossRate")
            allowableLossRate = StrToDouble(paramValue);
         else if(paramName == "BreakEvenTriggerPips")
            breakEvenTriggerPips = StrToInteger(paramValue);
         else if(paramName == "TrailIntervalPips")
            trailIntervalPips = StrToInteger(paramValue);
      }
   }
   
   FileClose(fileHandle);
   return true;
}

