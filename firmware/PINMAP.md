# Pin map (provisional — DK bring-up, not the real PCB)

Picked for nRF52-DK convenience so this firmware has somewhere real to run
before the rev1 PCB exists. Replace this table (and `app/boards/nrf52dk_nrf52832.overlay`)
once actual routing is known in Phase 3.

| Pin | Function | Peripheral |
|---|---|---|
| P0.02 | PDM CLK | MEMS mic |
| P0.03 | PDM DIN | MEMS mic |
| P0.04 | SPI SCK | LCD driver IC (PCF8551) |
| P0.05 | SPI MOSI | LCD driver IC |
| P0.06 | SPI CS | LCD driver IC |
| P0.07 | GPIO in, pull-up, active low | Top-right button (native: START/STOP — repurposed: **Talk**) |
| P0.08 | PWM0 | Stock piezo buzzer |
| P0.09 | PWM1 | Vibration motor (via transistor driver, not direct GPIO drive) |
| P0.10 | GPIO in, pull-up, active low | Top-left button (native: LIGHT — kept as backlight toggle) |
| P0.11 | GPIO in, pull-up, active low | Bottom-left button (native: MODE — repurposed: **music transport**) |
| P0.12 | GPIO in, pull-up, active low | Bottom-right button (native: ADJUST/SET — repurposed: **thought capture**) |

## Button remapping (rev1 firmware decision, not from the source spec)

The stock A158W has four buttons (confirmed layout: top-left LIGHT,
top-right START-STOP, bottom-left MODE, bottom-right ADJUST/SET) and the
spec doesn't say how to divide talk / capture / music / call-answer across
them — this is a firmware-level UX call, documented here so it's easy to
revisit once the watch is in hand:

- **Top-left**: unchanged, backlight toggle.
- **Top-right**: repurposed as **Talk** (press = talkStart, release =
  talkEnd).
- **Bottom-left**: repurposed as **music transport** — short press =
  play/pause, double-press = next, long-press = previous. No dedicated
  volume buttons in rev1 (BT earbuds/phone already have volume control;
  lowest-value AVRCP action to cut for button budget).
- **Bottom-right**: repurposed as **thought capture** — press-and-hold =
  holdStart, release = holdEnd (matches the spec's literal "press-and-hold,
  speak, release" wording).
- **Incoming call override**: while a call is ringing, top-right press =
  answer and bottom-right press = reject, temporarily overriding their
  normal meaning for the duration of the ring.
- Alarm time/mode and other legacy Casio menu settings are assumed to be
  configured from the phone app (consistent with time/weather already being
  phone-driven), not via on-watch button navigation — MODE's traditional
  cycling function is not preserved.

Not wired to the MCU at all:
- **NFC**: fully passive (NTAG213-class IC + antenna coil only) — no MCU
  pins, no firmware involvement. A phone tap talks to it directly over the
  RF field even with a dead battery.
- **Battery**: power rail only (VDD/GND via the case's spring contacts —
  see `../hardware/FEASIBILITY.md`), not a GPIO.
