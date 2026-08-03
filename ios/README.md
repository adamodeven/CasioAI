# CasioAI iOS app

Phase 1 of the build (see `../GOALS.md`). This is source-complete for the
app's feature set, but it was written in an environment with no macOS/Xcode
toolchain to compile against — **you are the first compiler this code sees.**
Expect a handful of small build errors on first open, most likely in the
spots called out under "Known risk areas" below.

## Build

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you don't have it:
   ```
   brew install xcodegen
   ```
2. Generate the Xcode project (the `.xcodeproj` itself isn't checked in —
   `project.yml` is the source of truth):
   ```
   cd ios
   xcodegen generate
   open CasioAI.xcodeproj
   ```
3. In Xcode, select the `CasioAI` target → **Signing & Capabilities** → set
   your personal team under **Team** (free Apple ID is fine for a local
   device install; re-signing is needed roughly every 7 days on a free
   account).
4. Build & run to a physical **iPhone 15 Pro or newer** — required for the
   on-device Foundation Models title generation in thought capture. (Speech
   transcription and everything else works on any iOS 26 device; only the
   title-generation step needs Apple Intelligence hardware.)
5. In the app's **Settings** tab, add:
   - An OpenAI API key (for live voice conversation via the Realtime API).
   - A Notion integration token + the target database's ID, then tap
     **Verify** to confirm it resolves.
   - A manual lat/lon for weather if you'd rather not grant Location access.

## What will and won't work without the watch

There's no watch firmware yet (that's Phase 2) — nothing broadcasts the BLE
service this app scans for, so:
- **Works now:** Settings, weather fetch (Home tab), and the app's own UI.
- **Inert until firmware exists:** BLE connection state will sit at
  "Scanning" forever, and anything gated on a watch button press (Talk,
  Capture) won't fire since there's no hardware to send `talkStart` /
  `holdStart` events. `TalkView`'s on-screen mic button calls the same
  `beginTurnFromApp()` path a watch press would, so it's a way to
  smoke-test the OpenAI Realtime plumbing without hardware — but it still
  needs `ble.audioFrameStream()` to produce audio, which today only a real
  watch (or a hand-rolled CoreBluetooth peripheral simulator) can do.

## Known risk areas (unverified against current docs/compiler)

- **Liquid Glass API surface** (`glassEffect`, `GlassEffectContainer`,
  `.buttonStyle(.glass)` / `.glassProminent`) — used throughout `TalkView`,
  `HomeView`, `SettingsView`. Written from the iOS 26 SDK's documented shape;
  double-check exact modifier signatures if these don't compile as-is.
- **Foundation Models framework** (`TitleGenerator.swift`) —
  `SystemLanguageModel.default.availability` and `LanguageModelSession.respond(to:)`
  are the documented entry points as of this writing; re-check against
  current Apple docs if this doesn't compile.
- **OpenAI Realtime API event schema** (`OpenAIRealtimeClient.swift`) — event
  names (`session.update`, `response.audio.delta`, etc.) and the `gpt-realtime`
  model id match the GA API's documented shape; this is the fastest-moving
  piece of the stack, so diff against OpenAI's current Realtime API reference
  before relying on it.
- **BLE GATT contract** (`WatchProtocol.swift`) — this is the *spec*, not
  something to debug against real hardware yet. It becomes real once Phase 2
  firmware implements the same UUIDs/payloads.

## Project layout

```
CasioAI/
  App/            App entry point, root TabView
  Bluetooth/      WatchProtocol (GATT contract) + BLEManager (central role)
  Voice/          OpenAI Realtime client, audio resampling/playback, Talk UI
  Capture/        On-device transcription (Speech) + title gen (Foundation
                   Models) + Notion hand-off, Capture UI
  Notion/         Notion API client
  Weather/        Open-Meteo client + location
  Call/           CallKit observer <-> watch call relay
  Music/          System music player <-> watch transport/volume relay
  Settings/       User-configurable settings (Keychain + UserDefaults)
  Security/       Keychain wrapper
  Home/           Status dashboard
  Models/         Shared AppEnvironment (dependency container)
```
