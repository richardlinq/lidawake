# lidawake

**English** | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md)

Keep your MacBook working with the lid closed — screen dark, screen locked,
everything still running. No external display, no dock, no power adapter required.

Built and verified on a fanless M4 MacBook Air, macOS 26.

## The problem

`caffeinate` does not do this. It holds a `PreventUserIdleSystemSleep`
assertion, which blocks **idle** sleep. Closing the lid is a different code
path — clamshell sleep — and it fires regardless:

```
$ ioreg -c IOPMrootDomain -r -d 1 | grep 'Last Sleep Reason'
"Last Sleep Reason" = "Clamshell Sleep"
```

The switch that actually governs it is the kernel-level `SleepDisabled` flag,
flipped by `sudo pmset -a disablesleep 1`.

## What lidawake does

Closing the lid:

```
save current brightness  →  lock the screen  →  set backlight to 0
```

Opening it: brightness is restored within a second, you unlock with Touch ID,
and whatever was running never stopped.

A background daemon decides when to hold, so you never have to remember
anything:

| Situation | Behaviour |
|---|---|
| On AC power | hold — battery level ignored |
| On battery, ≥ threshold (default 20%) | hold |
| On battery, below threshold | release, normal sleep returns |

Two modes, one command to flip between them:

- **Keep Running** — lid close keeps working
- **Let It Sleep** — stock macOS behaviour, nothing intercepted

## Requirements

- macOS on Apple Silicon (Intel probably works; untested)
- Xcode Command Line Tools (`xcode-select --install`) — one 40-line C file is
  compiled at install time
- One `sudoers.d` rule, scoped to three exact `pmset` invocations

## Install

```bash
git clone https://github.com/richardlinq/lidawake.git
cd lidawake
git checkout v0.1.0   # or stay on main for the newest, less settled, state
./install.sh
```

See [CHANGELOG.md](CHANGELOG.md) for what each release changed and, more
importantly, what is known to be wrong with it.

The installer shows you the exact sudoers lines before asking for your
password, and validates them with `visudo -c` before installing anything.

## Usage

```bash
lidawake                 # status
lidawake toggle          # flip between the two modes
lidawake auto            # Keep Running
lidawake normal          # Let It Sleep (stock behaviour)

lidawake threshold 25    # change your reserve (never below the hard floor)
lidawake calibrate       # measure this machine, derive its hard floor
lidawake blank off       # stop dimming the backlight on lid close
lidawake lock  off       # stop locking the screen on lid close
lidawake run -- CMD      # hold only while CMD runs, then restore and notify
```

Optional Raycast commands live in `raycast/` — add that directory under
Raycast Settings → Script Commands.

## How it works, and what we measured

Most of this was not obvious and had to be measured. The findings, in case
they save you the same afternoon:

**`SleepDisabled=1` also disables display sleep.** With the flag set, the lid
closes and the panel stays lit. This is *not* an assertion problem — 51 seconds
after the lid shut, `UserIsActive=0`, `PreventUserIdleDisplaySleep=0`, no
process holding anything, `displaysleep` set to 1 minute, and the backlight was
still on four minutes later. Both `pmset displaysleepnow` (returns 0, does
nothing) and the `displaysleep` idle timer are inert in this state. Turning off
sleep turns off the machinery that would have turned off the display.

So lidawake drives the panel directly through Apple's `DisplayServices`
(`bin/dispbright`, ~40 lines of C), which still works.

**`ioreg -c AppleARMBacklight` is not a measurement.** Sweeping brightness from
0.0 to 1.0 leaves `brightness`, `rawBrightness`, `BrightnessMicroAmps` and
`BrightnessMilliNits` completely unchanged. If you are trying to verify whether
the backlight is on, these fields will confidently tell you nothing. Use
`dispbright` — or just look at the screen.

**Display sleep, screen saver and screen lock do not pause computation.** Only
system sleep does. Locking the screen on lid close costs you nothing but a
Touch ID tap.

**`kDisp` in `pmset -g log` does not tell you whether the lid is shut.** Read
`AppleClamshellState` from `ioreg` instead.

## Where the battery threshold comes from

The default is 20%. That number is not a safety limit, and it is worth being
precise about why — because "20%" quietly bundles three unrelated concerns:

- **A safety floor** — below this there is not enough runway to release the hold
  and finish a clean sleep before the battery is empty. The only hard
  constraint, and the only one that can be derived.
- **A reserve** — how much charge you want left when you open the lid at your
  destination. A preference, not a limit.
- **Cell longevity** — repeated deep discharge ages lithium cells. Independent
  of this tool.

`lidawake calibrate` measures your machine and derives the first one:

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

The result is the interesting part: **shutting down safely costs about 1% of
charge.** Whatever justifies a 20% default, it is not the risk of running out
mid-sleep. Those other 19 points are reserve and cell longevity — both
legitimate, neither a safety argument.

The floor is clamped at 5%, and the clamp is honest about being a clamp: the
arithmetic models discharge rate and shutdown time, but not state-of-charge
gauge error, which is largest near empty and can be several points on an aged
cell. A reported 2% may really be 0%.

Your reserve is yours to set, and cannot be pushed below the floor:

```bash
lidawake threshold 10
```

Two limits of this derivation, stated plainly:

- Peak draw depends on whatever else is running, so repeated calibrations
  disagree. The floor only ratchets up — a quieter re-run will not erase a
  worse case already observed.
- We do not know whether macOS's own critical-battery hibernate still fires
  while `SleepDisabled=1`. That flag has already been shown to disable display
  sleep. If the failsafe is gone too, this threshold is the only line of
  defence rather than a convenience. Untested, because testing it means running
  a battery to zero.

## Verify it yourself

Do not take the above on faith — `lidtest` collects three independent lines of
evidence and refuses to pass unless all three agree:

```bash
lidtest start     # then close the lid, wait ~2 min, open it
lidtest report
```

It checks a heartbeat for gaps, macOS's own sleep log for Sleep/Wake events,
**and** whether the lid was genuinely shut. That third check matters: without
it, a green result only proves the machine does not idle-sleep, which
`caffeinate` already gave you.

## Security note

Keep Running breaks the chain that normally locks your Mac: lid close → sleep →
lock. That is why locking on lid close is **on by default**. If you turn it off
with `lidawake lock off`, closing your laptop no longer locks it, and anyone who
opens it lands on your desktop.

## Heat

A fanless MacBook Air dissipates through its chassis. Running a heavy workload
lid-closed on a desk is fine; doing it inside a bag will trap heat and throttle.
The battery threshold limits how long that can go on, but it is not a thermal
guard.

## Uninstall

```bash
./uninstall.sh
```

Restores stock behaviour, unloads the daemon, removes the symlinks and the
sudoers rule.

## License

Apache-2.0
