# CasioAI — Project Goals

Source spec: Casio A158W Custom Smartwatch Module handoff doc.

## What we're building

Replace the stock module in a Casio A158WE with a custom PCB, turning it into a
minimal, voice-first smartwatch paired to an iOS app. Three deliverables, in
priority order:

1. **Phone companion app** (iOS, real installable app) — fully built and functional
2. **Watch firmware** (BLE peripheral) — fully built and functional
3. **Rev1 PCB** — fabricatable Gerbers + BOM, ready to order and hand-assemble

This is a from-scratch design. Sensor Watch Pro's open-source firmware/hardware
is a reference to study, not a base to fork. Ollee Watch is closed and off-limits
as a source. End state is a fabricatable, unassembled rev1 — the user orders,
assembles, and tests; rev2 fixes happen in a follow-up pass.

## Working agreement

- Phased build order: **app → firmware → PCB**, since PCB layout depends on final
  component choices made in the other two phases.
- Post a brief status/plan at the *start* of each phase, not just a report at the end.
- Ask before silently deciding anything that changes the spec (MCU tradeoffs,
  connection-interval-vs-battery-life targets, what to cut if space runs out).
  Source anything sourceable (datasheet values, case dimensions, standard BLE
  library choices) instead of asking.
- Close out with a punch list: designed-but-unverified vs. known risk (NFC through
  steel case, exact stack height, battery life estimate), so the user knows what
  to physically test first.

## Phase 1 — Phone companion app (iOS)

- BLE central role: connect to watch, relay call answer/reject, relay music
  control (AVRCP), push time/date sync, push daily hi/lo temp.
- Audio pipeline: receive audio from watch (voice Q&A and thought-capture modes),
  send to Claude API.
  - Voice Q&A: send to Claude, return a spoken/text response to the user.
  - Thought capture: transcript + short AI-generated title, then create a Notion
    page (title = generated title, body = full transcript) in a specified
    inbox/todo database via the Notion API.
- Weather fetch: pull daily high/low from a weather API, push to watch over BLE.
- Real installable iOS app (not a script) — needs an Apple developer target
  (device profile vs. TestFlight vs. App Store) decided before build.

**Open decisions before starting this phase** (raised separately):
- Which Notion database is the thought-capture inbox (ID/name), and expected
  page schema.
- How the app authenticates to the Claude API (user-supplied key stored on
  device vs. a small backend proxy) and to Notion.
- Weather API provider (needs an API key/account).
- iOS distribution target for a personal/hand-built app (Xcode local install to
  a single device vs. TestFlight).

## Phase 2 — Watch firmware (BLE peripheral)

- MCU: research nRF52-series (or similar BLE SoC) candidates against power
  budget and package size; present options with tradeoffs rather than picking
  silently.
- BLE peripheral role, aggressive duty-cycling: loose connection interval when
  idle, tightened only during active use (voice capture, incoming call, active
  music control). Primary lever for the 3–6 month CR2016/2025 battery target —
  treated as a firmware design requirement, not an afterthought.
- Button/gesture handling (including press-and-hold for thought capture).
- Audio capture and buffering (MEMS mic) for streaming/buffering to phone.
- LCD segment driving: time/date, temp (hi/lo from phone), alarm state.
- Buzzer (reuse stock piezo) + vibration motor control, alarm modes.
- Low-power state management throughout.

## Phase 3 — Rev1 PCB

- Source A158W module cavity dimensions from teardown docs / modder guides;
  cross-check against Ollee Watch and Sensor Watch Pro form factors (same case
  family) as a sanity check on achievable size/depth.
- Source real datasheets for every component (MCU, mic, vibration motor, NFC
  IC, coin cell holder, buzzer if not reusing stock part) — build footprints
  from actual specs, not estimates.
- KiCad: schematic → footprint placement → routing → board outline matching
  cavity constraints.
- Coin cell: CR2016 or CR2025, decided by depth budget once stack height is known.
- Passive NFC tag placement — flagged explicitly as an unvalidated risk (steel
  case attenuation), not treated as solved by placement alone.
- Output: Gerbers + BOM + a written list of physical assumptions to verify with
  calipers before ordering (e.g., "cavity depth assumed at X mm from source Y,
  please verify").

## Explicit non-goals (rev1)

- No onboard speaker/speakerphone — call audio routes through phone/earbuds.
- No wireless or pogo-pin charging — coin cell in a screw-back door w/ O-ring only.
- No Android app.
- No case/exterior redesign — must fit the stock A158WE cavity.

## Definition of done for this handoff

- App and firmware are built and functional (not stubs).
- PCB phase produces fabrication-ready Gerbers + BOM, not an assembled/tested board.
- Final punch list delivered covering unverified assumptions and open risks
  (NFC-through-steel, stack height, battery life estimate) for physical testing.
