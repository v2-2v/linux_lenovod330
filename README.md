# linux_lenovod330

Alternative solution to the problem of the screen not resuming after
suspend on the Lenovo D330: safely turn off *just the backlight* on Lenovo
IdeaPad D330-10IGM / D330-10IGL
(Intel Gemini Lake, internal MIPI-DSI panel) — without triggering the
long-standing "black screen after suspend/DPMS" bug that affects this panel
family on Linux.

This started as a deep-dive into that resume bug (full write-up, in
Japanese: [qiita.com/v2-2v/items/5a0f0b72e93312a4a026](https://qiita.com/v2-2v/items/5a0f0b72e93312a4a026)).
The conclusion of that investigation was that the bug **cannot be reliably
fixed in software**, and the community-recommended workaround is to disable
suspend entirely and rely on the desktop's screen-blank/DPMS timeout
instead:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

The problem: **DPMS off/on reproduces the exact same bug**, even with
suspend completely out of the picture (same `intel_dsi_disable()` →
`intel_dsi_pre_enable()` cycle, same GPIO-based panel-power sequence). So
disabling suspend and then also disabling DPMS (to avoid the DPMS-triggered
version of the same bug) just leaves you with a screen that never turns off
at all — which is what several D330 setup guides end up recommending, and
what pushed this project.

## Confirmed working on

- **Hardware**: Lenovo IdeaPad D330-10IGM
- **OS**: Linux Mint 22.3 (Cinnamon, X11)

Should apply more broadly (see [The trick](#the-trick) below), but this is
the only combination actually verified end-to-end so far. The idle daemon
specifically is X11-only for now (via `xprintidle`) — Wayland support is
planned but not done yet; see the note under [Installing and configuring
the userspace
pieces](#installing-and-configuring-the-userspace-pieces-either-method).

**On Linux Mint specifically** (the exact environment this repo was
verified on), do these two first, before installing this repo:

1. [lucasgabmoreno/linuxmint_lenovod330](https://github.com/lucasgabmoreno/linuxmint_lenovod330)
   — the original community setup guide for this model on Mint (disables
   suspend, tames several other D330-on-Mint quirks). This repo builds on
   top of that baseline.
2. [v2-2v/linux_lenovod330-linuxmint-login-backlight-only-fix](https://github.com/v2-2v/linux_lenovod330-linuxmint-login-backlight-only-fix)
   — fixes a *different* trigger of this same underlying bug: the screen
   sometimes coming up backlight-only right at the login→desktop
   transition (Cinnamon auto-rotating the display forces a modeset). Works
   standalone on a stock kernel, independent of this repo's DKMS patch.

## Before you install: disable suspend AND your desktop's own screen-blanking

This tool is meant to be the *only* thing that ever touches the backlight.
If suspend is still enabled, or your desktop environment's own idle
screen-blank/DPMS-off is still active, you're right back to hitting the bug
this exists to avoid — both of those go through the same buggy panel
power/DSI re-init path. Two things need to be off before you go further:

**1. Suspend / hibernate** (systemd):

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

**2. Your desktop's own idle screen-blank / DPMS-off timeout.** On Linux
Mint (Cinnamon) — the environment this repo is verified on:

```bash
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-display-ac 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-display-battery 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
```

Other desktops (GNOME, KDE, XFCE...) have their own equivalent power
settings — same goal either way: nothing except this repo's idle daemon and
lid handler should ever be allowed to touch the display's power state.

## What this repository provides

- A small, targeted i915 kernel patch, packaged as a **DKMS module** so
  installing it is a `git clone` + a handful of commands — no full custom
  kernel required (a manual full-kernel build path is included too, as a
  fallback).
- Userspace glue (a systemd `--user` idle daemon and an `acpid` lid-switch
  handler) that uses the patch to turn just the backlight off after an idle
  timeout or on lid close, and back on on activity or lid open.

Together, these let you keep suspend disabled (the workaround above) while
still getting a screen that actually turns off — without hitting the
DPMS-triggered version of the same bug. See [The trick](#the-trick) below
for how the patch itself avoids that bug, and
[Installation](#installation--method-1-dkms-recommended) to just install it.

## The trick

On this panel, three GPIOs are exposed through the VBT (Video BIOS Table)
MIPI sequence bytecode, and are the *only* way any of GOP/Windows/i915 ever
touch the panel:

| VBT GPIO index | Function |
|---|---|
| 0 | Panel reset |
| 3 | Panel power rail (`PANEL1_VDDEN`) |
| 4 | Backlight enable (`PANEL1_BKLTEN`) |

Confirmed against the board schematic (Huaqin NB6067/T6066): **the backlight
enable line is circuit-independent from the panel power rail** — a separate
boost converter, a separate GPIO, no shared power domain. It is *only* the
panel-power/reset cycle (index 0/3) and the DSI protocol re-init that
trigger the known bug. Toggling *just* the backlight-enable GPIO never goes
near any of that.

The catch: index 3 and index 4 are **already held exclusively by the i915
driver** as `gpiod` consumers from probe time onward (confirmed with
`gpioinfo`: both show `[used]`, consumer `0000:00:02.0`). So this is not
something you can do with `gpioset`/`libgpiod` from userspace — it has to
happen from inside the i915 module itself.

This repo is a ~15-line patch to `intel_dsi_vbt.c` that adds a write-only
module parameter, `d330_backlight_gpio`, which calls the driver's own
existing `bxt_gpio_set_value()` directly on GPIO index 4 — completely
decoupled from the CRTC enable/disable state machine. Writing `0`/`1` to it
physically cuts/restores backlight power, with **zero interaction with the
buggy resume path.**

```
$ echo 0 | sudo tee /sys/module/i915/parameters/d330_backlight_gpio   # backlight off, panel stays live
$ echo 1 | sudo tee /sys/module/i915/parameters/d330_backlight_gpio   # backlight on
```

Verified on real hardware: true physical backlight cutoff (unlike
`/sys/class/backlight/*/brightness = 0`, which only reaches the panel's
minimum-brightness floor, not a true off), and clean, bug-free recovery
across dozens of on/off cycles, idle-timeout triggers, and lid close/open
events.

> **Should apply to any Gemini-Lake-class i915 platform with a VBT-driven
> DSI panel** where the backlight-enable GPIO is wired independently of the
> panel power rail — not just this one Lenovo model. Verify your own GPIO
> index (see [Adapting to a different panel](#adapting-to-a-different-panel)
> below) before assuming index 4 applies to you.

## Why not just...

- **Re-enable DPMS?** Reproduces the bug (see above).
- **`brightness=0` via the backlight class device?** Safe, but only reaches
  a hardware brightness floor — not a true off, and on this panel it was
  visibly still lit.
- **`gpioset`/libgpiod on the raw GPIO line?** Blocked — i915 already holds
  the descriptor exclusively.
- **Suspend/hibernate?** That's the bug this whole thing exists to avoid.

## What's in this repo

- `dkms/d330-i915-2.0/` — **method 1 (recommended):** a DKMS package —
  the full, patched `drivers/gpu/drm/i915` source plus `dkms.conf` and a
  `dkms-prebuild.sh` helper, building a drop-in `i915.ko` replacement
  against whatever kernel you're already running. No full kernel build.
- `patches/0001-d330-backlight-gpio-param.patch` — **method 2:** the same
  change as a standalone patch, for building a complete custom kernel by
  hand (what this project originally used, before packaging it as DKMS).
- `scripts/d330-backlight.sh` — thin wrapper: `off`/`on` → sysfs write
- `scripts/d330-backlight-idle.sh` — idle-timeout daemon (polls `xprintidle`)
- `scripts/d330-set-idle-timeout.sh` — change the idle timeout live, no restart
- `scripts/d330-backlight-idle.service` — systemd `--user` unit for the above
- `scripts/d330-lid.sh` + `scripts/d330-lid.event` — instant, event-driven
  lid close/open handling via `acpid`
- `scripts/90-d330-lid.conf` — `logind.conf.d` drop-in to stop
  `systemd-logind` from also handling the lid switch (avoids double-handling)

## Requirements

- A Gemini-Lake-class i915 machine with a VBT MIPI-DSI panel (confirmed on
  D330-10IGM; likely applies to D330-10IGL and similar Bay Trail/Cherry
  Trail/Gemini Lake DSI tablets — see the write-up for the list of affected
  vendors).
- Kernel headers matching your running kernel (`linux-headers-$(uname -r)`)
  and a working compiler toolchain (`build-essential` or equivalent) — DKMS
  needs these to build against your kernel; method 2 needs a full matching
  kernel source package instead.
- **Secure Boot must be disabled.** Verified on real hardware: even though
  `dkms build` (method 1) auto-generates a MOK and signs the module with
  it, turning Secure Boot back on with that MOK *not yet enrolled* in
  firmware results in `i915` silently not loading at all (no error, just
  absent from `lsmod`/`dmesg`) — no working display. In principle, one-time
  MOK enrollment (`sudo mokutil --import /var/lib/shim-signed/mok/MOK.der`,
  reboot, confirm at the blue "MOK Manager" screen) is supposed to let
  Secure Boot stay on for good, but that path hasn't been verified working
  here — treat "Secure Boot off" as the requirement for now. If you need
  Secure Boot on, use method 2 and sign the resulting kernel yourself with
  your own enrolled key. On the D330 specifically, tap **Fn+2** at power-on
  to get into firmware setup and toggle it off.
- `sudo` access.

## Installation — method 1: DKMS (recommended)

**Before you start: disable Secure Boot in firmware setup** (on the D330,
tap Fn+2 at power-on). See [Requirements](#requirements) above for why —
in short, the module gets signed but that signature isn't trusted by
default, so `i915` silently fails to load under Secure Boot as things
stand.

Builds and installs a drop-in `i915.ko` for the kernel you're already
running — no separate kernel, no new GRUB entry, no `grub-reboot` dance.
DKMS also rebuilds it automatically the next time your kernel updates.
Copy-paste the whole block below as-is:

```bash
git clone https://github.com/v2-2v/linux_lenovod330.git
cd linux_lenovod330

sudo apt-get install -y dkms linux-headers-$(uname -r) build-essential

sudo cp -r dkms/d330-i915-2.0 /usr/src/
sudo chmod +x /usr/src/d330-i915-2.0/dkms-prebuild.sh
sudo dkms add -m d330-i915 -v 2.0
sudo dkms build -m d330-i915 -v 2.0
sudo dkms install -m d330-i915 -v 2.0

# i915 is commonly loaded from the initramfs for early KMS -- rebuild it so
# the new module is what actually gets loaded at boot, not a stale cached copy
sudo update-initramfs -u

sudo reboot
```

After rebooting:

```bash
$ modinfo -F filename i915
/lib/modules/$(uname -r)/updates/dkms/i915.ko.zst      # confirms the DKMS build won, not the stock one

$ ls /sys/module/i915/parameters/ | grep d330_backlight_gpio
d330_backlight_gpio
```

**This module param alone does nothing by itself** — it just gives you a
knob. Continue to
[Installing and configuring the userspace pieces](#installing-and-configuring-the-userspace-pieces-either-method)
below to get actual idle-timeout and lid-close automation.

**Why the source is bundled instead of just the patch**: out-of-tree builds
of `drivers/gpu/drm/i915` hit a handful of headers that `#include` siblings
by a path that only resolves when the driver lives inside a real kernel
source tree (tracepoint headers, plus a couple of cross-references into
`display/`, `gt/`, and one header borrowed from
`drivers/platform/x86/intel_ips.h`). `dkms-prebuild.sh` symlinks those into
place inside your installed kernel headers before the build runs, without
touching any file that actually belongs to the `linux-headers` package —
see the script for exactly what it does. This is why the package ships the
whole driver directory (14MB) rather than just the one-file patch.

> **usr-merge warning:** if you ever hand-copy this package instead of
> using the commands above, don't `cp`/`tar` a `lib/`-rooted tree straight
> onto `/` on a system where `/lib -> usr/lib` is a symlink — you can end
> up replacing that symlink with a real directory and silently breaking
> every path through it. (Hit this once during development; not a risk
> with the `dkms add`/`cp -r .../usr/src/` flow above.)

### Removing it

```bash
sudo dkms remove -m d330-i915 -v 2.0 --all
sudo rm -rf /usr/src/d330-i915-2.0
sudo update-initramfs -u
```

## Installation — method 2: full custom kernel (manual patch build)

Only worth it if DKMS genuinely doesn't work for you (e.g. you can't get
matching kernel headers at all). This is heavier and riskier — you're
building and booting an entire replacement kernel, not just one module.

### 1. Apply the patch and build

```bash
cd /path/to/matching/linux-source-<version>
patch -p1 < patches/0001-d330-backlight-gpio-param.patch
make M=drivers/gpu/drm/i915   # fast incremental rebuild if the rest of the
                               # tree is already configured/built; otherwise
                               # do a normal full kernel build
```

Rebuild a **complete, self-contained kernel** (vmlinuz + all modules), not
just the one `.ko` — mixing a freshly built module into an already-running
stock kernel by ABI version alone is fragile (module versioning/symbol CRCs
need to match exactly; this is exactly the problem DKMS solves by building
against your *actual* installed headers instead). Install it as an
*additional* GRUB entry, leave `GRUB_DEFAULT` pointed at your existing,
known-good kernel, and use `sudo grub-reboot <new-entry-id>` for a one-shot
boot to test before making it permanent. This is the same safety pattern
used throughout the original investigation (see the write-up) — the custom
kernel is otherwise 100% stock behavior; this patch only ever does
anything when something explicitly writes to `d330_backlight_gpio`.

> **usr-merge warning:** if your target machine has `/lib -> usr/lib` as a
> symlink (most modern distros), do **not** `tar xzf ... -C /` a package
> whose archive has a top-level `lib/` directory straight onto `/` — `tar`
> will happily replace the `/lib` symlink with a real directory, silently
> breaking every path that resolves through it. Extract to a staging
> directory and copy the `lib/modules/<version>` tree into
> `/usr/lib/modules/<version>` instead.

### 2. Verify the module param exists

```bash
$ ls /sys/module/i915/parameters/ | grep d330_backlight_gpio
d330_backlight_gpio
```

**This module param alone does nothing by itself** — it just gives you a
knob. Continue to
[Installing and configuring the userspace pieces](#installing-and-configuring-the-userspace-pieces-either-method)
below to get actual idle-timeout and lid-close automation.

## Installing and configuring the userspace pieces (either method)

**Required regardless of which installation method you used above** — the
kernel module only exposes the on/off knob; these scripts are what actually
turn the backlight off on idle/lid-close and back on. Run this once
`d330_backlight_gpio` exists (verified above):

```bash
sudo install -m 755 scripts/d330-backlight.sh /usr/local/bin/d330-backlight.sh
sudo install -m 755 scripts/d330-backlight-idle.sh /usr/local/bin/d330-backlight-idle.sh
sudo install -m 755 scripts/d330-set-idle-timeout.sh /usr/local/bin/d330-set-idle-timeout
sudo install -Dm644 scripts/d330-backlight-idle.service /etc/systemd/user/d330-backlight-idle.service

# least-privilege sudo grant so the (unprivileged) idle daemon can flip the
# backlight without a password prompt, without granting it root generally
# (replace YOUR_USER with your actual username)
echo 'YOUR_USER ALL=(root) NOPASSWD: /usr/local/bin/d330-backlight.sh off, /usr/local/bin/d330-backlight.sh on' \
  | sudo tee /etc/sudoers.d/d330-backlight
sudo chmod 440 /etc/sudoers.d/d330-backlight
sudo visudo -cf /etc/sudoers.d/d330-backlight   # sanity-check syntax before trusting it

# idle-timeout daemon (5 min default; change anytime with d330-set-idle-timeout)
systemctl --user daemon-reload
systemctl --user enable --now d330-backlight-idle.service
d330-set-idle-timeout 5

# instant lid close/open handling
sudo apt-get install -y acpid
sudo install -m 755 scripts/d330-lid.sh /etc/acpi/d330-lid.sh
sudo install -m 644 scripts/d330-lid.event /etc/acpi/events/d330-lid
sudo mkdir -p /etc/systemd/logind.conf.d
sudo install -m 644 scripts/90-d330-lid.conf /etc/systemd/logind.conf.d/90-d330-lid.conf
sudo systemctl restart systemd-logind acpid
```

`xprintidle` is required by the idle daemon (`sudo apt-get install
xprintidle`); it needs an X11 session.

The kernel patch/module itself doesn't care about your desktop or display
server, but the idle daemon here is X11-only (via `xprintidle`) — Wayland
support (likely via the compositor's own idle-notify protocol) hasn't been
done yet and is planned (see [Confirmed working
on](#confirmed-working-on) above). `acpid`-based lid handling and the
plain `d330-backlight.sh off`/`on` script don't touch X11 at all, so those
should already work under Wayland as-is.

## Changing the idle timeout

```bash
d330-set-idle-timeout 10   # minutes; takes effect within ~2s, no restart needed
d330-set-idle-timeout off  # disable idle auto-off entirely (stops the service)
```

`off` stops the `d330-backlight-idle.service` systemd `--user` unit; running
`d330-set-idle-timeout <minutes>` again re-enables and restarts it. Lid
close/open handling (`acpid`) is a separate mechanism and keeps working
either way. Under the hood, setting a timeout just writes
`IDLE_MINUTES=10` to `~/.config/d330-backlight-idle.conf`,
which the daemon re-reads on every poll.

## Adapting to a different panel

If your panel's backlight-enable GPIO isn't VBT index 4, or your platform
isn't Gemini-Lake-class (`bxt_gpio_set_value`, `DISPLAY_VER(display) >= 9`
in `intel_dsi_vbt.c`), you'll need to find your own index before this is
useful:

1. Decode your VBT's MIPI sequence blocks (`MIPI_SEQ_BACKLIGHT_ON`) to find
   which GPIO index it uses — or just `grep -n "Starting MIPI sequence" `
   your `drm.debug=0x1e` boot log and correlate against
   `intel_dsi_vbt_exec_sequence()`.
2. Confirm it's circuit-independent from the panel power GPIO — check your
   board schematic if you have one, or empirically: toggle it while the
   panel is otherwise idle and confirm only the backlight is affected, with
   no DSI re-init log lines (`Starting MIPI sequence ...`) appearing.
3. Change the `4` in `bxt_gpio_set_value(d330_bl_connector, 4, !!value);`
   to your index.

## License

The scripts and documentation in this repo are BSD-3-Clause (see
`LICENSE`). `patches/0001-d330-backlight-gpio-param.patch` and
`dkms/d330-i915-2.0/` (which bundles actual Linux kernel source,
`drivers/gpu/drm/i915` and one header from `drivers/platform/x86`, plus our
patch on top) are GPL-2.0-only, matching the kernel they're built from,
regardless of this repo's overall license.

## Disclaimer

**Use at your own risk.** This involves running a patched kernel module (or,
with method 2, an entire custom kernel) and flipping GPIOs on real
hardware, and may involve disabling Secure Boot. None of that is
undoable-proof: a bad module/kernel, a wrong GPIO index adapted from this
patch, or a mistake following the install steps could leave a machine
unbootable, and in the worst case damage hardware. With method 2
specifically, follow the safe-boot pattern in its installation steps
(separate GRUB entry, pinned `GRUB_DEFAULT`, `grub-reboot` for one-shot
testing) every time — don't make an unverified custom kernel your only
boot option.

This is shared as-is, from a personal hardware investigation, with **no
warranty of any kind and no affiliation with Intel or Lenovo**. The author(s)
and contributors accept **no responsibility or liability for any damage** —
to hardware, data, software, or otherwise — arising from using, adapting,
or building on anything in this repository, including but not limited to a
bricked device. See `LICENSE` for the full, legally-binding disclaimer that
governs this repo's content; this section restates it in plain language for
anyone about to `grub-reboot` into a patched kernel and should not be read
as replacing it. If you're not comfortable with that level of risk, don't
run this — stick to the community-recommended workaround (mask the sleep
targets, live with the screen never blanking, or accept the DPMS-triggered
version of the bug).

## Background reading

The full investigation that led here — kernel/GOP/Windows-driver source
comparison, VBT bytecode decoding, board schematic analysis, and the long
process of ruling out fixes for the underlying resume bug before finding
this workaround — is written up on Qiita (Japanese):
[qiita.com/v2-2v/items/5a0f0b72e93312a4a026](https://qiita.com/v2-2v/items/5a0f0b72e93312a4a026).
