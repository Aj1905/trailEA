# trailEA

MT4/MT5用のトレーリングストップEA（Expert Advisor）です。注文時に自動でStopLossを設定し、利益が出たタイミングでStopLossを建値に戻し、その後は含み益に応じてStopLossを自動調整します。

## 機能

- **自動StopLoss設定**: 注文時に口座残高と許容損失率から初期StopLoss幅を自動計算して設定
- **建値へのStopLoss移動**: 一定以上の利益が出たタイミングでStopLossを建値に設定
- **トレーリングストップ**: 含み益が一定額増えるごとにStopLossラインを自動調整
- **証拠金維持率の自動取得**: 証券会社のロスカット水準などのパラメータを自動取得して計算に利用

## ファイル構成

- `trailEA.mq4`: MT4用のEAファイル
- `trailEA.mq5`: MT5用のEAファイル
- `trailEA.ini`: 設定ファイル（許容損失率、トリガーpip数、トレール間隔を設定）

## インストール方法

### MT4の場合
1. `trailEA.mq4`を`MetaTrader 4/MQL4/Experts/`フォルダにコピー
2. `trailEA.ini`を`MetaTrader 4/MQL4/Files/`フォルダにコピー
3. MetaTrader 4を再起動
4. ナビゲーターからEAをチャートにドラッグ&ドロップ

### MT5の場合
1. `trailEA.mq5`を`MetaTrader 5/MQL5/Experts/`フォルダにコピー
2. `trailEA.ini`を`MetaTrader 5/MQL5/Files/`フォルダにコピー
3. MetaTrader 5を再起動
4. ナビゲーターからEAをチャートにドラッグ&ドロップ

## 設定ファイル（trailEA.ini）

`trailEA.ini`ファイルで以下のパラメータを設定できます：

```ini
[TrailEA]
; 許容損失率（口座残高に対する損失の割合、0.01 = 1%）
AllowableLossRate=0.01

; StopLossを建値に戻すトリガーとなる含み益のpip数
BreakEvenTriggerPips=20

; トレールでStopLossラインを変化させる含み益のpip間隔
TrailIntervalPips=10
```

### パラメータ説明

- **AllowableLossRate**: 口座残高に対する許容損失率（0.01 = 1%、0.02 = 2%など）
  - この値に基づいて初期StopLoss幅が自動計算されます
  - 例: 口座残高が100,000円、許容損失率が0.01の場合、許容損失額は1,000円

- **BreakEvenTriggerPips**: StopLossを建値に戻すトリガーとなる含み益のpip数
  - この値以上の含み益が出ると、StopLossが建値に設定されます
  - 例: 20pipsの利益が出たら、StopLossを建値に移動

- **TrailIntervalPips**: トレールでStopLossラインを変化させる含み益のpip間隔
  - 建値に戻した後、この間隔ごとにStopLossが調整されます
  - 例: 10pipsごとにStopLossを調整（30pips利益で10pips分、40pips利益で20pips分のStopLossを設定）

## 動作の流れ

1. **注文時**: 口座残高と許容損失率から初期StopLoss幅を計算し、自動で設定
2. **利益発生時**: 含み益が`BreakEvenTriggerPips`に達すると、StopLossを建値に設定
3. **トレーリング**: その後、含み益が`TrailIntervalPips`ごとに増えるたびに、StopLossを調整
   - ロングポジション: 含み益が増えるとStopLossを上げる
   - ショートポジション: 含み益が増えるとStopLossを下げる

## 注意事項

- このEAは既存のポジションに対して動作します
- 証拠金維持率が低い場合は、より大きなStopLoss幅が設定されます
- 各証券会社の最小StopLevel（ストップレベル）を考慮して動作します
- 設定ファイルは`MQL4/Files/`または`MQL5/Files/`フォルダに配置してください

## 使用例

### 例1: 保守的な設定
```ini
AllowableLossRate=0.005      ; 0.5%の損失まで許容
BreakEvenTriggerPips=30       ; 30pipsの利益で建値に戻す
TrailIntervalPips=15          ; 15pipsごとに調整
```

### 例2: 積極的な設定
```ini
AllowableLossRate=0.02        ; 2%の損失まで許容
BreakEvenTriggerPips=15       ; 15pipsの利益で建値に戻す
TrailIntervalPips=5           ; 5pipsごとに調整
```

## ライセンス

このコードはFXトレード用の補助ツールです。使用は自己責任でお願いします。
