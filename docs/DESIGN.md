# Pace design

How Pace looks and behaves, and why. The code is the source of truth; this page explains its intent. Section numbers are referenced from code comments.

## 1. Principles

- **Glance and go.** The top of the panel answers "how much have I used, and when does it come back" in under a second.
- **Calm.** Time is shown in hours and minutes, never seconds. Color appears only when something needs attention. Changes are announced once.
- **Detail on request.** Rows open on click to show analysis the collapsed row does not have, never a repeat of it. Several can be open at once, and they stay open ([NN/g on accordions](https://www.nngroup.com/articles/accordions-on-desktop/)).
- **Nothing moves under the pointer.** Hover only highlights. The panel's window never moves or resizes while open.
- **Local and read only.** No server, no analytics. The Claude sign-in is only ever read.
- **Unofficial.** No Anthropic logos, wordmarks or mascots.

## 2. Surfaces

1. **Menu bar item.** An apple filled to the session level, and the time until the reset that matters now (for example "2h 15m"). Left click opens the panel; right click has Refresh, Settings, Start at Login and Quit.
2. **Panel** (360 pt wide). Opens under the icon, anchored to its right edge, in a fixed transparent window. Esc, a click elsewhere, or the icon closes it.
3. **Status pill.** A capsule that drops from under the icon for about three seconds when the status changes, like the Focus pill. Ignores the mouse.
4. **Shortcut.** ⌃⌥P by default, recordable in Settings, toggles the panel from any app.

## 3. Panel layout

| Block | Content |
|---|---|
| Hero | "Session" (or "Week" at the weekly limit). Two equal figures: percent used, and time until reset with the clock time under it. One bar. One line on pace ("On pace to last until the reset", or in orange "At this pace, it runs out around 1:05 AM"). |
| List | Week (reset always visible on its own line), model limits such as "Fable weekly", Credits (amount or "Off"), This week by product. Every value is "% used". |
| Open row | A bar with a tick where an even pace would be, "Day N of 7", and a daily budget. Credits: what is left before the cap. Products: one sentence of insight. |
| Footer | Sync time (or "Paused · numbers from …"), Usage ↗, Settings. |

Every button and number has a two-word hover label.

## 4. States

| State | When | Hero | Timer | Line under the bar |
|---|---|---|---|---|
| Normal | session under 100% | Session, % used | time until reset, "until 1:34 AM" | pace forecast, when there is enough of the window to judge |
| Fresh session | session window not started | Session, 0% | 5h, "starts with your next message" | none |
| Session limit | session at 100% | Session, 100% | orange, "back at 3:32 AM" | "+1 apple" when this window's apple was awarded |
| Weekly limit | week at 100% | Week, 100% | orange, "back Wed 6:42 AM" | weekly limit message; wording depends on whether credits are on |

A window whose reset time has passed is treated as full again, even before new data arrives. Reset and limit events are raised once per window (`EventGate`).

## 5. Motion

- Digits roll when a number changes (once a minute for the timer).
- The bar, opened rows and the Settings screen move with short springs.
- The pill drops in with a slight spring and fades out.
- The unseen "+1" dot pulses; the apple wiggles every few seconds.
- Reduce Motion turns all of it off.
- Repeating motion uses keyframe animations scoped to one view, never a repeating transaction that could animate the panel's layout.

## 6. Copy

- No em dashes or en dashes anywhere in the UI.
- Pill: "Session back · a fresh 5 hours", "New week · everything's full", "Session limit · back at 3:32 AM", "Weekly limit · back Wed 6:42 AM", "Running fast · runs out around 1:05 AM".
- Doomscroll comparisons in the apple popover, with words = tokens × 0.75: distance scrolled on a phone, Eiffel Towers tall, days of reading, tweets.

## 7. Visual tokens

- Background `#262624`, raised `#30302E`, text `#FAF9F5`, secondary `#C2C0B6`, muted `#9C9A92`, faint `#87867F`.
- Bars: track `rgba(250,249,245,0.10)`, fill `#FAF9F5`; orange at a limit.
- Accent (warnings) `#F0B38F`; gold (rewards) `#F2CD7E`.
- Apple: body `#D97757`, stem `#8A5A3A`, leaf `#8FB07A`. Paths (24 × 24):
  - body `M12 8.2C10.6 6.9 7.9 6.5 6 8C3.7 9.8 3.5 13.4 4.6 16.2C5.6 18.8 7.6 21.5 9.6 21.5C10.6 21.5 11.1 21 12 21C12.9 21 13.4 21.5 14.4 21.5C16.4 21.5 18.4 18.8 19.4 16.2C20.5 13.4 20.3 9.8 18 8C16.1 6.5 13.4 6.9 12 8.2Z`
  - stem `M12 8.2C12 6.1 12.4 4.5 13.4 3.3`
  - leaf `M12.9 5.3C13.6 3.3 15.8 2.5 17.8 3C17.2 5 15 6 12.9 5.3Z`
- Type: system font. Big figures 34 pt semibold rounded; rows 13 pt; captions 12 pt.

## 8. Data and polling

- **Status line source:** a Claude Code status line script saves session and week numbers to a local file, checked every 15 seconds (5 near a limit).
- **Sign-in source:** the usage endpoint, every 5 minutes (every minute near a limit or a reset), with backoff on failure and Retry-After respected.
- Failures keep the last numbers on screen. A sign-in that needs renewing pauses calmly and is re-checked locally every minute.
- See [SECURITY.md](../SECURITY.md) for how the sign-in is read.
