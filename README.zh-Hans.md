# lidawake

[English](README.md) | **简体中文** | [繁體中文](README.zh-Hant.md)

合上 MacBook 也继续运行 —— 屏幕变黑、屏幕锁定，但任务全程没停。
不需要外接显示器、不需要扩展坞，也不需要接电源。

在无风扇的 M4 MacBook Air、macOS 26 上开发并实测。

## 问题出在哪

`caffeinate` 做不到这件事。它持有的是 `PreventUserIdleSystemSleep`，挡的是**空闲**休眠。
合上盖子走的是另一条路径 —— clamshell sleep —— 照样会触发：

```
$ ioreg -c IOPMrootDomain -r -d 1 | grep 'Last Sleep Reason'
"Last Sleep Reason" = "Clamshell Sleep"
```

真正管这件事的是内核层的 `SleepDisabled` 标志，由 `sudo pmset -a disablesleep 1` 翻开。

## lidawake 做什么

合上盖子时：

```
记住当前亮度  →  锁定屏幕  →  背光设为 0
```

打开时：一秒内恢复亮度，用 Touch ID 解锁，而刚才在跑的东西从来没有停过。

后台守护进程负责判断什么时候该保持，你不需要记住任何事：

| 情况 | 行为 |
|---|---|
| 接着电源 | 保持 —— 不看电量 |
| 用电池，电量 ≥ 阈值（默认 20%） | 保持 |
| 用电池，低于阈值 | 松手，恢复正常休眠 |

两种模式，一条命令来回切：

- **Keep Running** —— 合上继续跑
- **Let It Sleep** —— macOS 出厂行为，什么都不拦截

## 环境要求

- Apple Silicon 的 macOS（Intel 应该也能跑，但没测过）
- Xcode Command Line Tools（`xcode-select --install`）—— 安装时会编译一个 40 行的 C 程序
- 一条 `sudoers.d` 规则，只放行三个明确的 `pmset` 命令

## 安装

```bash
git clone https://github.com/richardlinq/lidawake.git
cd lidawake
./install.sh
```

安装程序会在要密码**之前**，先把那三行 sudoers 规则的原文打印给你看，
并且用 `visudo -c` 验证通过才写入系统 —— 验证不过就整个中止，什么都不会装。

## 使用

```bash
lidawake                 # 查看状态
lidawake toggle          # 在两种模式之间切换
lidawake auto            # Keep Running
lidawake normal          # Let It Sleep（出厂行为）

lidawake threshold 25    # 改你的余量（不得低于硬底线）
lidawake calibrate       # 测量这台机器，推导它的硬底线
lidawake blank off       # 不要在合盖时压暗背光
lidawake lock  off       # 不要在合盖时锁定屏幕
lidawake run -- CMD      # 只在 CMD 执行期间保持，跑完自动恢复
```

`raycast/` 里有四个 Raycast 命令，在 Raycast Settings → Script Commands 添加该目录即可。

## 工作原理，以及我们实测到的东西

下面这些大多不直觉，都是量出来的。写下来，希望能帮你省掉一个下午：

**`SleepDisabled=1` 会连屏幕休眠一起关掉。** 标志翻开之后合上盖子，面板会一直亮着。
这**不是** assertion 的问题 —— 合上 51 秒后，`UserIsActive=0`、
`PreventUserIdleDisplaySleep=0`、没有任何进程持有相关 assertion、`displaysleep` 设成 1 分钟，
而四分钟后背光依然亮着。`pmset displaysleepnow`（返回 0，但什么都没发生）
和 `displaysleep` 空闲计时器在这个状态下**都是失效的**。
你让系统别睡，它就连「把屏幕关掉」那套机制也一起停用了。

所以 lidawake 改成通过 Apple 的 `DisplayServices` 直接驱动面板
（`bin/dispbright`，约 40 行 C），那条路还通。

**`ioreg -c AppleARMBacklight` 不是测量值。** 把亮度从 0.0 扫到 1.0，
`brightness`、`rawBrightness`、`BrightnessMicroAmps`、`BrightnessMilliNits`
四个字段**纹丝不动**。如果你想用它们判断背光开着没，它们会非常有自信地告诉你一堆毫无意义的数字。
请改用 `dispbright` —— 或者最简单，直接用眼睛看屏幕。

**屏幕休眠、屏幕保护程序、锁定屏幕都不会暂停运算。** 只有系统休眠会。
合盖时顺手锁屏，代价只是多按一下 Touch ID。

**`pmset -g log` 里的 `kDisp` 不能用来判断盖子有没有合上。**
请改读 `ioreg` 的 `AppleClamshellState`。

## 电量阈值这个数字是怎么来的

默认值是 20%。**这不是一个安全数字**，而且值得把话讲清楚 —— 因为「20%」悄悄把三件性质完全不同的事绑在一起了：

- **安全底线** —— 低于这个电量，就来不及松手并完成一次干净的休眠，电池会先耗尽。
  这是唯一的硬约束，也是唯一可以推导出来的。
- **抵达余量** —— 你到目的地打开盖子时希望还剩多少电。这是偏好，不是限制。
- **电池寿命** —— 反复深度放电会加速锂电池老化。这跟这个工具无关。

`lidawake calibrate` 会实际测量你这台机器，推导出第一项：

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

结果本身才是重点：**安全地睡下去只要花大约 1% 的电。** 不管 20% 这个默认值是靠什么撑起来的，
反正不是「怕睡到一半没电」。剩下那 19 个百分点买的是抵达余量和电池寿命 ——
两者都成立，但两者都不是安全论证。

底线被夹在 5%，而且这个夹值老实承认自己就是个夹值：上面的算式只建模了掉电速度和关机耗时，
**没有建模电量计本身的误差**，而电量计恰恰在接近空的时候最不准，老化的电池可能差好几个百分点。
显示 2% 可能实际上是 0%。

余量由你决定，但不能低于底线：

```bash
lidawake threshold 10
```

这套推导有两个限制，直说：

- 峰值功耗取决于当下还有什么在跑，所以每次校准结果都不一样。底线只会往上走 ——
  安静时重跑一次，不会洗掉先前观测到的更坏情况。
- 我们不知道 `SleepDisabled=1` 的时候，macOS 自己那套「电量见底强制休眠」还有没有效。
  这个标志已经被证实会停用屏幕休眠。如果连那道保险也一起没了，那这个阈值就是**唯一的防线**
  而不是便利设计。没测过，因为要测就得把一颗电池放到 0。

## 自己验证，不要相信我

上面那些请不要照单全收 —— `lidtest` 会收集三项互相独立的证据，三项全过才算通过：

```bash
lidtest start     # 然后合上盖子，等约 2 分钟，再打开
lidtest report
```

它会检查心跳有没有断层、macOS 自己的睡眠日志有没有 Sleep/Wake 事件，
**以及盖子到底有没有真的合上**。第三项很关键：少了它，一份全绿的报告
只证明了「机器不会空闲休眠」，而那件事 `caffeinate` 本来就做得到。

## 安全性提醒

Keep Running 会打断「合上 → 休眠 → 锁定」这条原本联动的链。
所以合盖时自动锁屏是**默认开启**的。如果你用 `lidawake lock off` 关掉它，
合上笔记本就不再锁定，任何人打开盖子都会直接进到你的桌面。

## 散热

无风扇的 MacBook Air 靠整块机身散热。放在桌上盖着跑重负载没问题，
但**塞进包里**会积热降频。电量阈值限制了这种状况能持续多久，但它不是散热保护。

## 卸载

```bash
./uninstall.sh
```

恢复出厂行为、停止守护进程、移除 symlink 与 sudoers 规则。

## 许可证

Apache-2.0
