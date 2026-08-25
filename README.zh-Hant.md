# lidawake

[English](README.md) | [简体中文](README.zh-Hans.md) | **繁體中文**

蓋上 MacBook 也繼續運作 —— 螢幕變黑、螢幕鎖定，但任務全程沒停。
不需要外接螢幕、不需要擴充座、也不需要接電源。

在無風扇的 M4 MacBook Air、macOS 26 上開發並實測。

## 問題出在哪

`caffeinate` 做不到這件事。它掛的是 `PreventUserIdleSystemSleep`，擋的是**閒置**休眠。
蓋上蓋子走的是另一條路徑 —— clamshell sleep —— 照樣會觸發：

```
$ ioreg -c IOPMrootDomain -r -d 1 | grep 'Last Sleep Reason'
"Last Sleep Reason" = "Clamshell Sleep"
```

真正管這件事的是核心層的 `SleepDisabled` 旗標，由 `sudo pmset -a disablesleep 1` 翻開。

## lidawake 做什麼

蓋上蓋子時：

```
記住目前亮度  →  鎖定螢幕  →  背光設為 0
```

打開時：一秒內還原亮度，用 Touch ID 解鎖，而剛才在跑的東西從來沒有停過。

背景守護程序負責判斷什麼時候該撐住，你不需要記得任何事：

| 情況 | 行為 |
|---|---|
| 接著電源 | 撐住 —— 不看電量 |
| 用電池，電量 ≥ 門檻（預設 20%） | 撐住 |
| 用電池，低於門檻 | 放手，恢復正常休眠 |

兩種模式，一個指令來回切：

- **Keep Running** —— 蓋上繼續跑
- **Let It Sleep** —— macOS 出廠行為，什麼都不攔截

## 環境需求

- Apple Silicon 的 macOS（Intel 應該也能跑，但沒測過）
- Xcode Command Line Tools（`xcode-select --install`）—— 安裝時會編譯一支 40 行的 C 程式
- 一條 `sudoers.d` 規則，只放行三個明確的 `pmset` 指令

## 安裝

```bash
git clone https://github.com/richardlinq/lidawake.git
cd lidawake
./install.sh
```

安裝程式會在要密碼**之前**，先把那三行 sudoers 規則的原文印給你看，
並且用 `visudo -c` 驗證過才寫入系統 —— 驗不過就整個中止，什麼都不會裝。

## 使用

```bash
lidawake                 # 查看狀態
lidawake toggle          # 在兩種模式之間切換
lidawake auto            # Keep Running
lidawake normal          # Let It Sleep（出廠行為）

lidawake threshold 25    # 改你的餘量（不得低於硬底線）
lidawake calibrate       # 量測這台機器，推導它的硬底線
lidawake blank off       # 不要在蓋上時壓暗背光
lidawake lock  off       # 不要在蓋上時鎖定螢幕
lidawake run -- CMD      # 只在 CMD 執行期間撐住，跑完自動還原並通知你
```

`raycast/` 裡有四個 Raycast 指令，在 Raycast Settings → Script Commands 加入該目錄即可。

## 運作原理，以及我們實測到的東西

底下這些大多不直覺，都是量出來的。寫下來，希望能幫你省掉一個下午：

**`SleepDisabled=1` 會連螢幕休眠一起關掉。** 旗標翻開之後蓋上蓋子，面板會一直亮著。
這**不是** assertion 的問題 —— 蓋上 51 秒後，`UserIsActive=0`、
`PreventUserIdleDisplaySleep=0`、沒有任何行程持有相關 assertion、`displaysleep` 設成 1 分鐘，
而四分鐘後背光依然亮著。`pmset displaysleepnow`（回傳 0，但什麼都沒發生）
和 `displaysleep` 閒置計時器在這個狀態下**都是失效的**。
你叫系統別睡，它就連「把螢幕關掉」那套機制也一起停用了。

所以 lidawake 改成透過 Apple 的 `DisplayServices` 直接驅動面板
（`bin/dispbright`，約 40 行 C），那條路還通。

**`ioreg -c AppleARMBacklight` 不是測量值。** 把亮度從 0.0 掃到 1.0，
`brightness`、`rawBrightness`、`BrightnessMicroAmps`、`BrightnessMilliNits`
四個欄位**紋風不動**。如果你想用它們判斷背光開著沒，它們會非常有自信地告訴你一堆毫無意義的數字。
請改用 `dispbright` —— 或者最簡單，直接用眼睛看螢幕。

**螢幕休眠、螢幕保護程式、鎖定螢幕都不會暫停運算。** 只有系統休眠會。
蓋上時順手鎖定螢幕，代價只是多按一下 Touch ID。

**`pmset -g log` 裡的 `kDisp` 不能用來判斷蓋子有沒有闔上。**
請改讀 `ioreg` 的 `AppleClamshellState`。

## 電量門檻這個數字是怎麼來的

預設值是 20%。**這不是一個安全數字**，而且值得把話講清楚 —— 因為「20%」悄悄把三件性質完全不同的事綁在一起了：

- **安全底線** —— 低於這個電量，就來不及放手並完成一次乾淨的休眠，電池會先耗盡。
  這是唯一的硬約束，也是唯一可以推導出來的。
- **抵達餘量** —— 你到目的地打開蓋子時希望還剩多少電。這是偏好，不是限制。
- **電池壽命** —— 反覆深度放電會加速鋰電池老化。這跟這個工具無關。

`lidawake calibrate` 會實際量測你這台機器，推導出第一項：

```
Battery   : 4242 mAh full (design 4629 mAh, health 91%), 11224 mV
Peak draw : 2242 mA on 10 cores = 25.2 W
Sleep img : 4502 MB, disk 1525 MB/s

Derivation
  discharge at peak load     0.88 %/min
  detect (poll interval)     10 s
  write hibernate image      5.9 s  (2x margin)
  + fixed overhead           5 s
  --------------------------------
  time to sleep safely       20.9 s
  charge consumed in that    0.31 %
  x safety factor            3
  --------------------------------
  derived from discharge     1 %
  gauge-error clamp          5 % (not derived — see note)
  ================================
  HARD FLOOR                 5 %
```

結果本身才是重點：**安全地睡下去只要花大約 1% 的電。** 不管 20% 這個預設值是靠什麼撐起來的，
反正不是「怕睡到一半沒電」。剩下那 19 個百分點買的是抵達餘量和電池壽命 ——
兩者都成立，但兩者都不是安全論證。

底線被夾在 5%，而且這個夾值老實承認自己就是個夾值：上面的算式只模型化了掉電速度和關機耗時，
**沒有模型化電量計本身的誤差**，而電量計恰恰在接近空的時候最不準，老化的電池可能差好幾個百分點。
顯示 2% 可能實際上是 0%。

餘量由你決定，但不能低於底線：

```bash
lidawake threshold 10
```

這套推導有兩個限制，直說：

- 峰值功耗取決於當下還有什麼在跑，所以每次校準結果都不一樣。底線只會往上走 ——
  安靜時重跑一次，不會洗掉先前觀測到的更壞情況。
- 我們不知道 `SleepDisabled=1` 的時候，macOS 自己那套「電量見底強制休眠」還有沒有效。
  這個旗標已經被證實會停用螢幕休眠。如果連那道保險也一起沒了，那這個門檻就是**唯一的防線**
  而不是便利設計。沒測過，因為要測就得把一顆電池放到 0。

## 自己驗證，不要相信我

上面那些請不要照單全收 —— `lidtest` 會蒐集三項互相獨立的證據，三項全過才算通過：

```bash
lidtest start     # 然後蓋上蓋子，等約 2 分鐘，再打開
lidtest report
```

它會檢查心跳有沒有斷層、macOS 自己的睡眠日誌有沒有 Sleep/Wake 事件，
**以及蓋子到底有沒有真的闔上**。第三項很關鍵：少了它，一份全綠的報告
只證明了「機器不會閒置休眠」，而那件事 `caffeinate` 本來就做得到。

## 安全性提醒

Keep Running 會打斷「蓋上 → 休眠 → 鎖定」這條原本連動的鏈。
所以蓋上時自動鎖定螢幕是**預設開啟**的。如果你用 `lidawake lock off` 關掉它，
闔上筆電就不再鎖定，任何人打開蓋子都會直接進到你的桌面。

## 散熱

無風扇的 MacBook Air 靠整塊機殼散熱。放在桌上蓋著跑重負載沒問題，
但**塞進包包裡**會積熱降頻。電量門檻限制了這種狀況能持續多久，但它不是散熱保護。

## 移除

```bash
./uninstall.sh
```

恢復出廠行為、停止守護程序、移除 symlink 與 sudoers 規則。

## 授權

Apache-2.0
