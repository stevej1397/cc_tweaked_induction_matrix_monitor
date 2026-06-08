# Induction Matrix Monitor

A CC:Tweaked program that displays and controls two Mekanism induction matrices
(critical + general) and graphs 12 hours of fill history on a 4x3 advanced
monitor array.

Power flow expected: `Generators -> Critical Matrix -> General Matrix -> Power Sink`.

The computer toggles two redstone signals to gate the flow:

| Gate                  | Opens when      | Closes when     |
|-----------------------|-----------------|-----------------|
| Critical -> General   | Critical >= 75% | Critical <= 70% |
| General  -> Sink      | General  >= 90% | General  <= 85% |

The 5% hysteresis prevents the gates from rapidly flapping on/off.

## Hardware setup

1. **Computer** -- Advanced Computer (so monitor output can be colored).
2. **Monitor** -- 4 wide x 3 tall *Advanced* Monitors fused into a single
   surface. Attach via wired modem.
3. **Wired modems** on both Mekanism Induction Ports. The peripheral name is
   typically `inductionPort_0`, `inductionPort_1`, etc. -- run `peripherals`
   on the computer to see actual names.
4. **Redstone wiring** (any combination of these works):
   - Direct from a side of the **computer** to the cable, or
   - Through one or more CC:Tweaked **Redstone Relays** (attached via
     wired modem). Each gate can drive multiple outputs at once -- e.g.
     "computer's left side *and* `redstone_relay` top *and*
     `redstone_relay_1` north" -- all toggled together.

   Configure the Mekanism universal cables with the **Configurator** ->
   *Redstone control* -> **High** (active only when receiving a signal).

   With `gate_signal = "high_opens"` (default), the computer emits
   redstone when it wants the gate **open**. If the computer dies, all
   gates lose signal and close -- a safe failure mode.

## Install

On the computer:

```
wget run https://raw.githubusercontent.com/stevej1397/cc_tweaked_induction_matrix_monitor/main/installer.lua
```

The installer downloads everything from this repo, fetches
[pixelbox_lite](https://github.com/9551-Dev/pixelbox_lite) for the history
graph, and runs **`setup`** (interactive) on a fresh install -- it detects
your matrix ports, monitor, *and* every redstone-output peripheral
(relays, integrators), asks which is which, then for each gate lets you
add as many `{peripheral, side}` outputs as you want (the computer's own
sides + any/all relay sides, mixed freely). Then it runs `check`.

## Reconfigure

Run `setup` any time to re-do the configuration interactively. Your old
config is backed up to `config.lua.bak` first. Or edit `config.lua` by
hand and re-run `check`.

## Commands

| Command   | What it does                                           |
|-----------|--------------------------------------------------------|
| `monitor` | Start the live monitor loop (also runs on boot)       |
| `setup`   | Interactive reconfigure -- detects peripherals, prompts |
| `check`   | Validate peripherals, sides, thresholds, pixelbox     |
| `update`  | Re-run the installer to pull the latest version       |

`update` keeps your `config.lua`. A fresh default is always dropped into
`config.example.lua` for reference. Use `update --reconfigure` (or
`setup`) to redo the interactive picks.

## Files installed

```
/installer.lua
/startup.lua          # auto-runs monitor on boot
/monitor.lua          # main program
/setup.lua            # interactive configurator
/check.lua            # pre-flight checks
/update.lua           # one-shot self-update
/config.lua           # user-editable settings (written by setup)
/pixelbox_lite.lua    # from 9551-Dev/pixelbox_lite
/lib/util.lua
/lib/peripherals.lua
/lib/history.lua      # 1440-sample ring, persisted to /history.dat
/lib/control.lua
/lib/render.lua
/lib/graph.lua
/history.dat          # created at runtime; survives reboots
```

## How history persistence works

Every 30 seconds, the program reads both matrices and appends a sample
(`{t, critical_fill, general_fill, critical_input, critical_output,
general_input, general_output}`) to an in-memory ring buffer of 1440
samples (12 hours). After each append, the full buffer is serialized to
`/history.dat.tmp` and atomically renamed to `/history.dat`, so a crash
mid-write cannot corrupt the history.

On boot, `/history.dat` is loaded back. If it doesn't exist or fails to
parse, the buffer starts empty.

## Layout (60x30 chars, scale 0.5)

```
+-- title bar -----------------------------------------------+
| CRITICAL MATRIX            GENERAL MATRIX                  |
|  Energy / Capacity / Fill   Energy / Capacity / Fill       |
|  [######  ] bar             [###     ] bar                 |
|  Input / Output / ETA       Input / Output / ETA           |
|                                                            |
| POWER GATES                                                |
|  Critical -> General : [OPEN]   open >= 75%  close <= 70%  |
|  General  -> Sink    : [SHUT]   open >= 90%  close <= 85%  |
|                                                            |
| 12-HOUR FILL HISTORY            critical  general  grid    |
|  (pixelbox graph -- two coloured lines, 25/50/75/100% grid)|
| -12h     -9h     -6h     -3h                          now  |
+------------------------------------------------------------+
```

## Troubleshooting

- **`monitor not found`** -- run `peripherals`, copy the actual name into
  `config.monitor`.
- **`peripheral X is not an induction matrix`** -- you wrapped the
  wrong block. The peripheral must be a Mekanism *Induction Port*, not
  a casing or cell.
- **Graph is empty** -- expected on first boot. Comes up after the first
  30-second history sample.
- **Gates seem inverted** -- flip `gate_signal` between `"high_opens"`
  and `"low_opens"` in `config.lua`. Or change the cable's redstone
  mode with the Mekanism Configurator.
- **HTTP API errors during install** -- in `computercraft-common.toml`
  set `http.enabled = true`.

## External libraries

The installer fetches these alongside the program files:

- [pixelbox_lite](https://github.com/9551-Dev/pixelbox_lite) -- teletext pixel
  renderer, used for the 12-hour history graph on the monitor.
- [PixelUI v2](https://github.com/Shlomo1412/PixelUI-v2) -- GUI library used
  by the interactive `setup` wizard.
- [shrekbox](https://codeberg.org/ShreksHellraiser/shrekbox) -- PixelUI's
  underlying teletext renderer.

## License

MIT (this repo). Pixelbox Lite is MIT, (c) 9551Dev. PixelUI v2 is MIT,
(c) Shlomo1412. Shrekbox is MIT, (c) ShreksHellraiser.
