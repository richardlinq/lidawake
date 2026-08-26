# Changelog

## v0.1.0 — 2026-08-26

First tagged release. Everything below was verified by running it, not by
reading the code.

### What works

- Lid closed, machine keeps running. Verified: lid shut 535s, 114 heartbeat
  samples with no gap, zero Sleep/Wake events in macOS's own log.
- On lid close: saves the current brightness, locks the screen, sets the
  backlight to 0. On open: restores brightness within a second.
- A daemon holds or releases based on power state — on AC always, on battery
  above your reserve. It never expires, because it is a policy rather than a
  timer.
- `lidawake run -- CMD` holds only while a command runs, then restores and
  notifies. Survives SIGKILL: the daemon notices an abandoned wrapper and puts
  the mode back (verified, 2s).
- `lidtest` verifies the above with three independent lines of evidence and
  refuses to report success unless the lid was genuinely shut.
- `lidawake calibrate` measures peak draw, hibernate image size and disk
  throughput on your machine, and derives the battery floor from them.

### Known limitations — please read before installing

- **It needs root.** A `sudoers.d` rule grants passwordless `pmset -a
  disablesleep`. The rule is scoped to three exact commands and validated with
  `visudo -c` before installing, but it is still root.
- **Setting `SleepDisabled` also disables macOS's own display sleep.** Measured:
  51 seconds after the lid closed, every relevant assertion was clear and
  `displaysleep` was set to 1 minute, and the backlight was still on four
  minutes later. Both `pmset displaysleepnow` and the idle timer are inert in
  this state. The backlight dimming and screen locking in this tool exist only
  to repair that side effect — a side effect this tool causes.
- **Amphetamine does the same job without root, and does not cause that side
  effect.** Verified on the same machine: lid shut 660s, machine never slept,
  display turned off on its own after the normal 5-minute timer, screen locked.
  It is closed source and Mac App Store sandboxed. For most people it is
  probably the better choice, and this README would be dishonest not to say so.
- **Intel Macs are untested.** Developed on an M4 MacBook Air, macOS 26.
- **The 5% battery floor is a clamp, not a derived number.** The derivation
  gives about 1%; the clamp covers state-of-charge gauge error near empty,
  which the arithmetic does not model.
- **Unverified:** whether macOS's own critical-battery hibernate still fires
  while `SleepDisabled=1`. If it does not, the battery threshold is the only
  line of defence rather than a convenience.

### Being evaluated for the next release

`kPMSetClamshellSleepState` (selector 12 on `IOPMrootDomain`, from Apple's own
xnu sources) disables clamshell sleep specifically, **without root**, and
without touching display sleep. This is what Amphetamine uses; the mechanism is
open source at `x74353/CDMManager-Sample` (BSD-2-Clause, by Phil Dennis-Jordan).

If it holds up, the next release drops the sudoers rule, the backlight dimming
and the screen locking entirely — roughly half this tool exists to work around a
problem the right mechanism never creates. It is not adopted yet: a one-shot
call returned success and did nothing, because the setting appears to be tied to
the calling process. A process-held version compiles and runs but has not been
verified against a real lid close.
