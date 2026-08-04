# CasioAI watch firmware

Phase 2 of the build (see `../GOALS.md`). Targets the **nRF52832** locked in
during the Phase 1.5 hardware pass (`../hardware/FEASIBILITY.md`). This is
source-complete against the WatchProtocol contract, but — like the iOS app —
it was written in an environment with **no ARM toolchain, no nRF Connect SDK,
and no compiler to check it against.** Treat this as a first draft for your
own build to compile-check, not a verified build. Known risk areas are
called out below, ranked by how likely they are to need a fix first.

## Build

1. Install [nRF Connect SDK](https://developer.nordicsemi.com/nRF_Connect_SDK/doc/latest/nrf/installation.html)
   (NCS) via `nrfutil` or the nRF Connect for Desktop toolchain manager —
   this pulls in Zephyr, nrfx, and the ARM GCC toolchain as a `west`
   workspace. Any reasonably recent NCS version should work; nothing here
   depends on a bleeding-edge feature.
2. From inside the NCS toolchain environment:
   ```
   cd firmware/app
   west build -b nrf52dk_nrf52832
   west flash
   ```
   This builds against the nRF52-DK bring-up overlay (see below), not real
   rev1 hardware — there is no rev1 PCB yet.

## Why this targets a dev kit, not a custom board

A real Zephyr custom board definition (`boards/<vendor>/casioai_watch/`)
belongs to Phase 3, once actual PCB routing exists to define it from. Until
then, `app/boards/nrf52dk_nrf52832.overlay` remaps an nRF52-DK's GPIO pins to
stand in for the eventual custom board, using the pin assignments in
[`PINMAP.md`](PINMAP.md) — which are themselves provisional, picked for DK
convenience rather than measured from anything. This lets the same
application code run on real, purchasable hardware today (nRF52-DK + a
breadboarded PDM mic/LCD driver/etc.) for bring-up, before rev1 exists.

## Known risk areas, most to least likely to need fixing

1. **`app/boards/nrf52dk_nrf52832.overlay` pinctrl syntax.** Devicetree
   `NRF_PSEL(...)` pin-control macros are the least-verified syntax in this
   firmware — no compiler was available to check them. Cross-reference
   against a real NCS checkout's sample overlays before trusting this file.
2. **`lcd_driver.c`'s PCF8551 command protocol.** The exact opcodes (mode-set
   byte, display-RAM write command) are placeholders following the general
   shape of this class of segment driver IC, not transcribed from the full
   datasheet (this environment's web access couldn't fetch the PDF — see
   `hardware/FEASIBILITY.md`'s note on restricted access). Get the real NXP
   PCF8551 datasheet and check `pcf8551_send_command` /
   `pcf8551_write_display_ram` against it.
3. **`lcd_driver.c`'s segment/digit offset map.** The `SEG_OFFSET_*` and
   `SEG_BIT_*` constants are named placeholders, not a real segment map —
   that genuinely can't exist until someone continuity-tests the actual
   A158WE LCD glass (see `PINMAP.md`'s punch list item). Seven-segment
   digit encoding itself (`SEVEN_SEG_DIGITS`) is real and doesn't need
   re-deriving.
4. **`audio_capture.c`'s nrfx_pdm event struct shape.** Targets the
   `buffer_requested`/`buffer_released` pattern from nrfx v2/v3;
   cross-check `nrfx_pdm_evt_t` in your installed NCS's
   `modules/hal/nordic/nrfx/drivers/include/nrfx_pdm.h` if this doesn't
   compile.
5. **Connection parameters in `ble_service.c`** (`conn_param_idle` /
   `conn_param_active`) are starting-point guesses, not measured against
   real current draw. Tune toward the spec's 3-6 month CR2016 target once
   you can actually measure current on real hardware.
6. Everything else (GATT service structure, button gesture logic, PWM
   haptics, time/temp state tracking) follows Zephyr's documented API
   shapes as accurately as this environment's knowledge allows, but is
   still unbuilt code — expect the normal small first-compile fixes.

## What's a firmware-level decision, not from the source spec

- **Button remapping** — see [`PINMAP.md`](PINMAP.md#button-remapping). The
  spec didn't say how to divide talk/capture/music/call-answer across the
  stock A158W's four buttons; this firmware's mapping is a reasonable but
  revisable rev1 call, not something to treat as settled.
- **No battery fuel gauge** — `power.c` reports a fixed 100% battery level.
  A real estimate would read the nRF52832's internal VDD via SAADC against
  the CR2016 discharge curve; not implemented in rev1.
- **NFC needs no firmware at all** — it's a fully passive IC + antenna, not
  wired to the MCU. Nothing to write here; the risk is entirely physical
  (steel-case attenuation), tracked in `hardware/FEASIBILITY.md`.

## Project layout

```
app/
  CMakeLists.txt, prj.conf     Zephyr application build config
  boards/
    nrf52dk_nrf52832.overlay   DK bring-up pin mapping (see above)
  dts/bindings/display/
    nxp,pcf8551.yaml           Minimal devicetree binding for the LCD driver IC
  src/
    watch_protocol.h           C mirror of ios/CasioAI/Bluetooth/WatchProtocol.swift
    ble_service.[ch]           GATT service + session-mode connection interval switching
    buttons.[ch]                Four-button handling incl. call-ring override
    audio_capture.[ch]          PDM mic -> BLE audio streaming
    lcd_driver.[ch]              SPI driver for the external LCD segment driver IC
    haptics.[ch]                 Buzzer + vibration motor, alarm pattern
    power.[ch]                   Time/temp state, once-a-minute display/status tick
    main.c                       Wiring
PINMAP.md                        Pin assignments + button remapping rationale
```
