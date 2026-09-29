# Contributing

Thanks for looking. Pace is small on purpose, so most changes are welcome as long as they keep it small.

## Ground rules

- Local only. No telemetry, no servers, no accounts. A PR that adds a network call other than the usage endpoint will not be merged.
- Pace never renews or writes the Claude sign-in, and never runs Claude Code commands. The token is read through `/usr/bin/security` (and the private credentials file), kept in memory, sent only to the usage endpoint, never logged and never written to disk. Network requests use the ephemeral session from `OAuthUsageProvider.makeSession()`. Keep it that way; `SecurityTests` will tell you if you do not.
- No dependencies. The whole app is SwiftUI plus Foundation.
- No em dashes or en dashes in UI copy. The tests check.
- Repeating animations use `keyframeAnimator` or `phaseAnimator`, never `withAnimation(.repeatForever)`. A test checks this too; the repeating transaction animates the panel's own layout.
- Every button has a hover label (`.definer("...")`) of two words at most. A test checks.
- The panel's window never moves or resizes while open, and hovering never changes layout. Anything that grows (an opened row) animates inside the fixed window. `PanelLayoutTests` checks every state, with every row open, fits and is stable.
- An opened row adds information; it never repeats its collapsed line. A test checks.
- Time is shown in hours and minutes, never seconds. A test checks.
- Not an Anthropic product. No Anthropic logos, wordmarks or mascots.

## Setup

```
git clone https://github.com/Anirudh64210/pace.git
cd pace
swift run Pace --demo
```

`--demo` cycles through every state every 12 seconds so you can see the animations without waiting for a real limit. `swift test` runs the tests. `make check` exercises both real data sources. `make app` builds `build/Pace.app`.

Xcode works too: `open Package.swift`.

## Where things live

| Path | What |
|---|---|
| `Sources/Pace/Model` | Snapshot types, the state machine, panel text derivation, formatting, comparisons. Pure Swift, all unit tested. |
| `Sources/Pace/Providers` | The usage sources behind `UsageProvider`. Add a new source here. |
| `Sources/Pace/UI` | SwiftUI views. `Theme.swift` holds every color. |
| `Sources/Pace/App` | Entry point, `StatusItemController` (menu bar item, panel, right-click menu) and `AppState` (polling, sync status, events). |
| `Sources/Pace/System` | Notifications, settings, the status line installer, launch cleanup. |
| `scripts/pace-statusline.sh` | The Claude Code status line script. It is also embedded in `StatusLineScript.swift`; a test keeps the two identical. |
| `docs/` | `DESIGN.md` (how Pace looks and behaves, and why) and the demo video. |

## Sending a change

1. `swift test` passes.
2. `make demo` still matches `docs/DESIGN.md`.
3. If you touched a data source, say in the PR which live response shape you tested against, with values replaced.

Open an issue first for anything bigger than a screen.

By taking part you agree to the [code of conduct](CODE_OF_CONDUCT.md).
