# Hardware feasibility pass

Sourced ahead of firmware (see chat log / GOALS.md working-agreement update):
packaging constraints should gate MCU/component choice before firmware gets
written against a specific chip's peripheral map, since a rewrite there is
more expensive than a rewrite in a pre-firmware research doc. Web access in
this environment was restricted to a handful of domains (GitHub came
through; Crowd Supply, sensorwatch.net, Wikipedia, and most datasheet/blog
hosts returned 403 at the org's egress policy) — quotes below are search-
snippet sourced, not full page fetches. Treat every number here as
"sourced, not measured" until checked against the physical watch or the
linked primary datasheet.

## Case / cavity

| Value | Source |
|---|---|
| A158 case: 36.8 × 33.2 × 8.2 mm | community spec aggregation (straphabit.com A158 review) |
| F-91W case: 37.5 × 34.5 × 8.5 mm | Wikipedia (via search snippet) |
| Case back: stainless steel, 4 screws | community teardown references |
| Movement: Casio **module 593** across F-91W / A158 / A159 | multiple watch-database sources |
| Stock battery: **Renata CR2016** (20mm × 1.6mm), rated ~7yr | module 593 spec aggregation |

No source gave an official cavity **depth** number (Casio doesn't publish
module drawings publicly, and no teardown site had it in text). That's the
single most important number on the calipers list below — everything else
in this doc budgets against the 8.2mm *external* case thickness minus
crystal, case walls, and LCD stack, which is an estimate, not a measurement.

### The strongest reference point: Sensor Watch / Sensor Watch Pro

Both are open-source drop-in board replacements **for this exact case
family** (F-91W and A158), which makes them the best real-world proxy we
have for what fits:

- Original Sensor Watch: Microchip **SAM L22** (segment-LCD-controller
  built in — directly relevant since we're also driving the stock LCD),
  CR2016 coin cell, 0.6mm PCB.
- Sensor Watch Pro: **nRF52820** (BLE 5.2), same CR2016 coin cell, same
  case fit. This is a direct existence proof that an nRF52-class BLE SoC
  plus a CR2016 cell fits this cavity.
- Sensor Watch's plug-in "sensor board" connector budgets only **1mm of Z
  height** for add-on components ("you will likely be limited to QFN and
  LGA type parts; SOICs are too large, even SSOP is generally too thick") —
  a strong signal that whatever depth budget exists above the main board is
  very tight, sub-1mm tight in places.

**Conclusion:** CR2016 is the safe default cell (proven in this exact case
twice over), not CR2025 — go with CR2016 unless the calipers check below
finds unexpected slack. This resolves the open "CR2016 or CR2025" question
from GOALS.md.

### Battery contacts: reuse Casio's mechanism, don't add a holder

A dedicated SMD CR2016 holder (e.g. MPD's "ultra-low" part) is still ~3.1mm
tall — on top of the 1.6mm cell, that's 4.7mm, more than half the entire
case thickness. Casio's own design avoids this: the coin cell sits loose in
a compartment, held by spring contacts in the case/back-door assembly, not
by a holder soldered to the module. Rev1 should do the same — **gold-
plated contact pads on the PCB positioned to meet the case's existing
spring contacts**, no separate holder part. This needs the teardown photos
to get pad placement right (see punch list).

## MCU: two real candidates, not a silent pick

Both are Nordic nRF52-series, both are realistic for this cavity, and they
trade off against each other in a way that's worth your call rather than
mine:

| | **nRF52820** | **nRF52832** |
|---|---|---|
| Package | QFN40, **5×5mm** | QFN48, **6×6mm** |
| Flash / RAM | 256KB / 32KB | 512KB / 64KB |
| BLE | 5.2 | 5.0 |
| Digital mic support | **No PDM/I2S peripheral** — audio would go through the analog comparator/ADC path instead | **PDM peripheral with EasyDMA** — purpose-built for a digital MEMS mic, CPU stays asleep during capture |
| Proven case fit | **Yes** — this is the exact chip Sensor Watch Pro ships in, in this exact case family | Not proven in this case; 1mm larger per side (44% more area) than the confirmed-fit part |
| System OFF current | 0.6–1.1µA | ~0.3µA sleep (rough, not apples-to-apples source) |

The whole product is built around audio (voice Q&A + thought capture are
two of the three core features), and PDM+EasyDMA is the low-power way to
capture it — polling an ADC in software instead costs CPU-awake time on
every frame, working against the battery-life requirement. That pulls
toward **52832**. But it's a bigger, unproven-in-this-case package, and
"MCU doesn't fit" is a much worse discovery mid-firmware than "audio
capture uses more current than we'd like." That pulls toward **52820**.

I'd lean 52832 for the audio path, but this is exactly the kind of call the
original spec asked to be surfaced rather than picked silently — see the
question below.

## Other components (real parts, not estimates)

| Component | Candidate | Key spec |
|---|---|---|
| MEMS mic | TDK T3902 (bottom-port PDM) | 3.5×2.65×0.98mm, 185µA ultra-low-power mode |
| MEMS mic (smaller alt) | Same Sky bottom-port PDM family | as small as 2.75×1.85×0.90mm |
| Vibration motor | Vybronics coin ERM/BLDC, 6-7mm class | 6mm×2.5mm or 7mm×2.1mm — **2.1-2.5mm is a real bite out of an 8.2mm case**, flagged for the calipers list |
| Passive NFC IC | NXP NTAG213 (SOT658-1 / MOA-1 package) | bare IC is small (sub-2mm class); the antenna coil area and steel-case detuning are the actual risk, not chip size — unchanged from the existing GOALS.md risk flag |
| Coin cell | Renata CR2016 | 20mm × 1.6mm, proven in this case twice over (see above) |

## Calipers-verification punch list (update to GOALS.md's list)

1. **Cavity depth** — no published source has this; everything above is
   budgeted against 8.2mm external case thickness minus an estimated
   crystal/case-wall/LCD stack. This is the top-priority physical
   measurement before any layout starts.
2. **Battery compartment geometry** — exact shape/position of Casio's
   spring contacts in the case-back assembly, so the PCB's contact pads can
   be placed to meet them without a separate holder.
3. **Vibration motor clearance** — confirm a 2.1-2.5mm-thick coin motor
   actually has room once the LCD, PCB, and battery are stacked; this is
   the component most likely to force a size compromise.
4. **MCU package fit** — once you pick 52820 vs 52832 below, confirm the
   larger 52832 (6×6mm) actually clears the available board area next to
   the LCD connector/crystal keep-out zones.

## Open decision

MCU choice (52820 vs 52832) is asked separately since it changes firmware's
audio-capture architecture, not just the BOM.
