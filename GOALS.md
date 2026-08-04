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

- Phased build order: **app → hardware feasibility/component selection →
  firmware → PCB layout/routing**. Originally planned as app → firmware → PCB;
  revised because MCU/component package selection is gated by physical cavity
  space, and discovering a fit problem after firmware is written around a
  specific chip's peripherals is a more expensive redo than checking fit
  first. Full board layout/routing still comes last, once firmware locks in
  exact pin/peripheral requirements.
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
- Audio pipeline: receive audio from watch (voice Q&A and thought-capture modes).
  - **Voice Q&A (live conversation)**: stream to the **OpenAI Realtime API**
    (not Claude) — this is a deliberate deviation from the original handoff doc,
    chosen because the Realtime API is purpose-built for low-latency spoken
    conversation.
  - **Thought capture**: transcribed and titled **entirely on-device**, no cloud
    call for this path.
    - Transcription: Apple's on-device `Speech` framework
      (`SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`).
    - Title generation: Apple's on-device Foundation Models framework (Apple
      Intelligence on-device LLM). Confirmed target hardware is iPhone 15 Pro+
      with Apple Intelligence enabled, so no heuristic fallback is needed for
      rev1.
    - Resulting transcript + title are written to Notion (see below).
- Notion integration: create a page (title = generated title, body = full
  transcript) in a database the user configures in the app's **Settings**
  screen (name/ID, not hardcoded) — supports switching inbox databases without
  a rebuild.
- Weather fetch: pull daily high/low from a weather API, push to watch over BLE.
- Real installable iOS app (not a script), installed via a **local Xcode build
  to the user's device** (free Apple ID, personal team — no paid Developer
  Program account for rev1). Note: free-account builds need re-signing roughly
  every 7 days; acceptable for rev1 per user.

**Resolved decisions:**
- Claude API is no longer in the phone app's audio pipeline for rev1 — replaced
  by OpenAI Realtime (conversation) and on-device Apple frameworks (thought
  capture). Where the original doc referenced "Claude API" for these two
  features, this supersedes it.
- Notion database target: user-configurable in Settings, not fixed at build time.
- iOS distribution: local Xcode install to the user's own device.

- OpenAI Realtime API key: stored on-device (Keychain), same approach as the
  Notion API token — no backend proxy for rev1.

**Still open before/during this phase** (source or ask as needed):
- Weather API provider (needs an API key/account).

## Phase 1.5 — Hardware feasibility & component selection

Pulled forward from Phase 3 (see working agreement above). Findings in
[`hardware/FEASIBILITY.md`](hardware/FEASIBILITY.md). Summary:

- **Coin cell: CR2016**, not CR2025 — resolved. It's the stock cell for this
  case family's module (593) and the one both Sensor Watch and Sensor Watch
  Pro use as drop-in boards for this exact case, so it's proven to fit twice
  over.
- **Battery contacts**: reuse Casio's own spring-contact mechanism (case
  back + O-ring) via gold-plated PCB pads, rather than adding a discrete SMD
  coin cell holder — a holder alone is ~3.1mm tall, too much of an 8.2mm
  case budget.
- **MCU: nRF52832** — resolved. Chosen over the proven-fit nRF52820 for its
  PDM+EasyDMA mic path (low-power capture, two of three core features are
  audio), accepting the risk of an unproven, 1mm-larger-per-side package.
  Cavity fit for the 6×6mm QFN48 is now a firmware-blocking calipers item.
- Mic, vibration motor, and NFC IC candidates sourced with real
  datasheet-level specs — see FEASIBILITY.md for parts and the tightest
  clearance risk (vibration motor thickness).
- No published source gives the module's cavity **depth** — flagged as the
  top-priority calipers measurement before any board layout starts.

## Phase 2 — Watch firmware (BLE peripheral)

Source-complete in [`firmware/`](firmware/) — nRF Connect SDK / Zephyr,
implementing the full WatchProtocol contract. Unbuilt/unverified against a
real compiler; see `firmware/README.md`'s risk-ranked list before trusting
any one file. Notable addition beyond the original spec: the stock A158W's
four physical buttons needed a rev1 UX mapping (talk/capture/music/call-answer
weren't assigned to specific buttons anywhere) — see
`firmware/PINMAP.md#button-remapping`.

- MCU: **nRF52832**, locked in from the Phase 1.5 decision above.
- BLE peripheral role, aggressive duty-cycling: loose connection interval when
  idle, tightened only during active use (voice capture, incoming call, active
  music control). Primary lever for the 3–6 month CR2016/2025 battery target —
  treated as a firmware design requirement, not an afterthought.
- Button/gesture handling (including press-and-hold for thought capture).
- Audio capture and buffering (MEMS mic) for streaming/buffering to phone.
- LCD segment driving: time/date, temp (hi/lo from phone), alarm state. Needs
  a dedicated external LCD driver IC (nRF52832 has no built-in segment LCD
  controller, unlike the SAM L22 Sensor Watch uses) — new BOM line found
  during firmware work, see FEASIBILITY.md addendum.
- Buzzer (reuse stock piezo) + vibration motor control, alarm modes.
- Low-power state management throughout.

## Phase 3 — Rev1 PCB

- Component selection done in Phase 1.5 (`hardware/FEASIBILITY.md`); this
  phase is layout/routing against firmware's finalized pin requirements.
- KiCad: schematic → footprint placement → routing → board outline matching
  cavity constraints.
- Passive NFC tag placement — flagged explicitly as an unvalidated risk (steel
  case attenuation), not treated as solved by placement alone.
- Output: Gerbers + BOM + a written list of physical assumptions to verify with
  calipers before ordering (e.g., "cavity depth assumed at X mm from source Y,
  please verify") — builds on the punch list started in Phase 1.5.

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
