# UI redesign: singing coach

Written mock-up descriptions for the singing-coach version of Fonos. The redesign keeps the prototype's visual world so the app still feels like the same product. What changes is the job each screen does.

## 1. What stays

- **Ground and cards:** dark slate (`#0F1316` ground, `#1A2025` cards), dark by default, with a full light theme.
- **Type:** Sora for numerals, titles, and tracked caps; Atkinson Hyperlegible Next for everything you read.
- **Icons:** the custom 24 pt, 1.8 pt-stroke set, extended with singing icons (section 7).
- **Layout:** WHOOP-style headline rings, Apple Health-style measure cards, and the weekday practice row.
- **Big primary action:** one 132 pt round button.
- **Stream colors:** mic amber, left accelerometer teal, right accelerometer violet, used only for the sensors.

## 2. What changes

| Before (prototype) | After (singing coach) |
|---|---|
| Speak tab: talk, get translated | **Sing** tab: pick an exercise, sing a take, get coached |
| Fold view: mic between two piezo envelopes | **Pitch lane + throat strip:** the live pitch line over target notes, with the left/right vibration fold beneath it |
| Rings: Clarity, Strength, Pace | Rings: **In tune**, **Steady**, **Range** |
| Quick phrases | Exercise cards |
| Translation card | **Feedback card** (headline, wins, one focus, drill) |

## 3. Color tokens

States get their own tokens and never borrow metric or stream hues (a finish-review finding on the prototype).

| Role | Token | Dark | Light |
|---|---|---|---|
| In tune ring | `metric.tune` | `#5AA9E6` sky | `#1F6FB2` |
| Steady ring | `metric.steady` | `#E77FA3` rose | `#B0456A` |
| Range ring | `metric.range` | `#A6CE5C` lime | `#5C7A1E` |
| Other measures | `metric.*` | Ink with their own icon; no extra hues | |
| Recording | `state.recording` | `#FF6B5E` | `#C0342B` |
| Primary action | `action` | `#3CC8B4` | `#0A8A7A` |
| Trend up / down | `state.trend` | Ink with ↑ / ↓ arrow glyph; never color alone | |
| Low signal | `state.caution` | `#F5A524` | `#A36100` |

In tune versus off is never shown by color alone. The live pitch line gets thicker inside the ±25 cent band, and the tuning needle shows a check mark at center.

## 4. Navigation

- Tabs: **Sing**, **Progress**, **Band**.
- Settings: the settings icon at the top left of Sing and Progress (sheet).
- Live exercise and feedback appear as a full-screen cover over Sing, so nothing on the tab bar distracts mid-take; they are dismissed with a large **Done** button.

## 5. Screens

### 5.1 Sing (home)

First viewport, top to bottom:

1. **Toolbar:** settings icon (left); status pill, centered ("Band ready", or "Check band fit" in caution); band battery (right).
2. **Today card:**
   - title "Today" in tracked caps
   - one line: "3 takes · 12 min" or "Ready when you are"
   - the three mini rings (In tune, Steady, Range) at 44 pt, with units inside
3. **Throat strip (live, idle):** the Fold view, reduced to 72 pt tall. Left accelerometer teal above the midline, right violet below, mic amber along it. It moves when the singer hums, which doubles as a constant fit check. Side labels sit in a left gutter outside the plot.
4. **Up next:** a large card for the suggested exercise (for example, "Five-note scale in D"), with the reason underneath ("Your last focus was landing notes") and the 132 pt **Sing** button centered beneath it.

Below the fold:

- **Exercises** grid: two columns of 72 pt tiles (Warm-up siren, Five-note scale, Sustained note, Arpeggio, Song phrase, Speaking-voice check), each with its icon and duration.
- **Earlier today:** a list of takes with their headlines; tap to reopen the feedback.

Empty state, first run: the Today card becomes "Let's find your range", with a **Start** button that leads to fit check, then range finder.

### 5.2 Live exercise (full-screen cover)

Built to be read from arm's length while singing:

- **Top:** exercise name and take number (body); **Stop** button (60 pt, top right).
- **Target note:** the target note in Sora at 96 pt ("F#3"), with the next note small beside it.
- **Tuning needle:** a 180° arc from −50 to +50 cents. The needle shows the current pitch; the center zone (±25 cents) is a quiet band with a check mark when the singer is inside it. The words "a little low" or "a little high" appear under it for 1 s after 300 ms off-target (never flashing).
- **Pitch lane** (the signature; 40% of the screen):
  - a scrolling piano-roll with target notes as rounded bars
  - the singer's pitch as a continuous line, drawn monotone (no invented wiggles), thicker inside the in-tune band
  - vibrato shows as its real wave
  - note names on the left gutter
- **Throat strip** (bottom, 88 pt): the live left/right fold from the accelerometers. In Technical mode, small chips show vibrato rate, extent, and onset type when a note ends.
- **States:**
  - count-in: three soft beats with a reference tone if enabled
  - recording: pulsing coral dot in the header, still under Reduce Motion
  - low signal: caution banner "Can't feel the band on the left. Adjust it and try again."

### 5.3 Feedback (after each take)

- **Header:** headline in Sora title (for example, "More in tune than your usual"), the take's three rings beneath at 72 pt, and a confidence notice if low.
- **Summary:** one or two sentences in body text.
- **Wins:** up to two rows, each a check disc plus the metric's icon plus one sentence.
- **Focus card** (the main element):
  - tracked-caps title "Focus"
  - the observation in title3
  - "Why it matters" in secondary text
  - the drill name and two to four numbered steps
  - a full-width **Try the drill** button
- **Next target:** "Next time: aim to land notes in 180 ms", with the ring partially filled toward it.
- **Technical detail** (Technical mode only): a collapsible row with the technical note and a per-note table (note, cents, settle ms).
- **Bottom bar:** **Sing again** (primary), **Next exercise**, **Done**.
- **Provenance line** in footnote text: "Feedback by Claude from your measurements. Your audio stayed on this iPhone." When the local coach produced the card: "Quick feedback (offline)."
- **Loading:** the local card appears at once; a thin progress bar under the headline shows the LLM refinement, and the card cross-fades when it lands (no layout jump; text reflows in place).

### 5.4 Progress

Same structure as the prototype:

- **Range control:** segmented Week / Month / 3 Months.
- **Rings:** In tune (%), Steady (%), Range (semitones). They become full-width rows at accessibility text sizes.
- **Weekly insight card:** written by the local coach from trends, in the same voice as the feedback. For example: "Your held notes are steadier than a month ago. Landing the first note is still your biggest gain."
- **Voice range card:** a horizontal keyboard strip (C2–C6) with the comfortable range highlighted, and the previous month's range as an outline so growth is visible.
- **All measures:** Apple Health-style cards for each measure group (Pitch, Vibrato, Loudness, Tone, Throat vibration), each showing:
  - a colored icon and title
  - the latest value with its unit
  - a mini bar chart with the last bar in the measure's color
  - "Exploratory" measures carry a small outlined tag
- **Days practiced:** the WHOOP weekday check row.

### 5.5 Measure detail

- The value with its unit and the period caption after it ("71% in tune · this month"), with no tracked-caps label above the number.
- Trend vs baseline: ink text with an ↑ or ↓ glyph.
- Chart: monotone line with daily points marked, a dashed baseline rule, and the y-axis fitted to the data.
- "What this means", "How it's measured" (with the sensor icons that feed it), and for exploratory measures, "Why this is exploratory".

### 5.6 Band

- **Device card:** band status, battery, and a **Check fit** button.
- **Sensor cards:**
  - Microphone (amber): live trace and level in dBFS
  - Left accelerometer (teal): live trace and contact state
  - Right accelerometer (violet): live trace and contact state
- **Balance card:** left/right share with a neutral title (not a stream color).
- **Fit check flow:** "Hum any comfortable note". Live left and right bars, then a pass or a specific instruction ("Move the band a little to the right").

### 5.7 Settings (sheet)

| Section | Contents |
|---|---|
| Coaching | Coaching level (Beginner / Technical detail); voice type; goals |
| Feedback | "Personal feedback with Claude" toggle; "What leaves your phone" explainer; "Use my goals in feedback" toggle |
| Practice | Reference tone on/off; count-in; auto-stop after silence |
| Your data | Save takes on this iPhone (off by default); Export; Delete everything |
| Appearance | Dark / Light / Match iPhone |
| About | Not a medical device; version; open-source font licenses |

### 5.8 Onboarding (first run, four screens)

1. **"Sing better, one take at a time."** A short promise and an animated pitch lane.
2. **"Your voice stays on your iPhone."** The privacy promise in three bullets, with the feedback toggle off by default.
3. **Fit check.**
4. **Range finder.** Ends on the first suggested exercise.

## 6. Signature interaction: the pitch lane

- The singer sees their voice as a line laid over the notes they're aiming for. Landing a note shows as the line settling onto the bar; vibrato shows as a wave around it.
- After a take, the same lane replays as a static summary in the feedback card's technical detail. The focus note is highlighted, so feedback points at an actual moment.
- Motion: the lane scrolls at a constant 2 s per screen width. With Reduce Motion, the lane holds still and notes advance in steps.

## 7. Icons to add

All drawn in the existing grid and stroke:

| Icon | Motif |
|---|---|
| sing | Open mouth with a note |
| tune | Needle at center of an arc |
| steady | Flat line through a held bar |
| range | Keyboard strip with brackets |
| vibrato | Even sine segment |
| onset | Step into a line |
| breath | Rising curve |
| tone | Concentric half-rings |
| accelLeft, accelRight | Sensor chip with vibration arcs on its side |
| drill | Repeat loop |
| exercise tiles | Siren (rising glide), scale (stairs), sustained (long bar), arpeggio (skipping stairs), song (two beamed notes), speak (speech bubble) |

## 8. Accessibility

- Targets: Sing 132 pt; exercise tiles 72 pt; Stop 60 pt; nothing under 44 pt.
- **VoiceOver:**
  - The live exercise announces the target note on each change.
  - A rotor action "Current pitch" speaks "F sharp 3, 12 cents low" on demand, never continuously.
  - Feedback reads headline → focus → drill.
- **Not color alone:** in tune vs off uses line thickness, the check mark, and words. Trends use arrows.
- **Haptics:** a light tick on landing in tune (optional, on by default), so the singer can keep their eyes off the screen.
- **Dynamic Type:** the target note and needle scale up; the pitch lane keeps a minimum height of 30% of the screen; rings reflow to rows.
- **Hearing:** every audio cue (count-in, reference tone) has a visual equivalent.

## 9. Carried-over fixes from the prototype review

- State colors separated from metric and stream colors (section 3).
- Every ring shows its unit.
- No eyebrow labels above numbers (5.5).
- Monotone charts with marked points and fitted axes (5.5).
- Live-chart labels in a gutter, not on the trace (5.1).
- Balance card title in neutral ink (5.6).
