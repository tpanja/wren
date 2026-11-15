# UI design

## Who it's for

The person living with ALS who wears the band and holds the phone. Their speech is hard for others to understand, and their hand control is declining. Every design decision starts from two facts: being understood is urgent, and effort is expensive.

## Direction

The screenshots supplied for inspiration set the look:

- **From WHOOP:** three headline rings with rounded numerals, tracked uppercase card titles, a plain-language insight card, and the weekday check row.
- **From Apple Health:** summary cards with a colored symbol and title, a large value with its unit, and a small trailing bar chart whose last bar carries the color.

**Signature: the Fold view.** On the Speak screen, the contact-mic waveform runs along the midline. The left piezo's vibration rises above it in teal and the right piezo's falls below it in violet, both at the same scale. When both sides vibrate equally the shape is a mirror image; when one side weakens the shape goes lopsided. Symmetry, one of the measures, can be seen without reading a number.

## Color

Each stream and measure keeps its color everywhere it appears.

The light palette is taken from a photo of the Fonos band (exposure-corrected against the white shell, then snapped to web-safe values). Surfaces use light tints of the backdrop grey.

| Role | Light | From the band | Dark |
|---|---|---|---|
| Card | `#FFFFFF` | White shell | `#1A2025` |
| Ground | `#F2F2F2` (wells `#EBEBEB`, rules `#D6D6D6`) | Grey backdrop `#CCCCCC`, tinted | `#0F1316` |
| Text | `#000000`, `#4D4D4D`, `#666666` | Black strap | `#F1EFEA` |
| Left piezo / Clarity / Speak | `#339999` | Green wire | `#3CC8B4` |
| Right piezo / Symmetry | `#6699CC` | Blue wire | `#8E7CF0` |
| Mic / Strength | `#999966` | Grey-green liner | `#F2B33D` |
| Pace | `#333333` | Black strap, softened | `#5AA9E6` |
| Steadiness, Listening | `#FF6666` | Red wire | `#E77FA3`, `#FF6B5E` |
| Pauses | `#999999` | Grey-green clip | `#A6CE5C` |

The accents sit near 3:1 on white: fine for fills, rings, and traces, not for small text. Each has a deeper shade of the same hue for labels and links (`leftInk #006666`, `rightInk #336699`, `micInk #666633`, `steadinessInk #CC3333`, `pausesInk #666666`), and the app tint uses `#006666`.

Light is the default. Settings offers Dark and Match iPhone, and every token has a dark variant (`Fonos/Design/Theme.swift`).

**Surfaces.** Every card is a `Surface`: white, a 1 pt warm edge, a tight contact shadow, and a wide soft lift, all tinted warm brown rather than black. In dark, surfaces separate by tone and cast no shadow. Radii are 22 pt for cards and 18 pt for tiles, always continuous corners.

**Signature details.** The Speak button is an `Orb`: the state color with a top-left sheen, a bright upper rim, a soft colored glow, and a quiet halo ring at rest. Range pickers are Fonos's own `SegmentedPicker`, a warm well with a white thumb that glides between options. Rings sit on a tinted track of their own color, and Apple Health–style mini bars show history in a 18% tint of the measure's color with the latest bar solid.

## Type

Two bundled faces, both under the SIL Open Font License (`Fonos/Resources/Fonts`, licenses alongside):

- **Atkinson Hyperlegible Next** for all reading and interface text. The Braille Institute designed it for low-vision readers, with letterforms that stay distinct (I, l, 1; O, 0). That matters when patients read back their own translated words, often at large sizes.
- **Sora** for numerals, screen titles, and tracked uppercase card titles. Its wide geometric figures carry the rings and big values, as in the WHOOP references.

Both are variable fonts registered at launch (`FonosType.register()`), so no Info.plist entries are needed. SwiftUI text uses `Font.ui(_:_:)` and `Font.metric(_:weight:)`, which scale with Dynamic Type through `relativeTo:`. Navigation titles, tab labels, and segmented controls get the same faces through UIKit appearance (`FonosType.applyAppearance()`).

## Icons

Fonos draws its own icon set rather than using SF Symbols: 22 SVG template images in `Assets.xcassets/Icons`, all on a 24 pt grid with a 1.8 pt rounded stroke. They come from the product's own motifs:

| Icon | Motif |
|---|---|
| Speak | A speech bubble carrying a waveform |
| Progress | Open concentric rings |
| Band | A collar with three sensor beads (left piezo, mic, right piezo) |
| Symmetry | Mirrored lobes on a dashed axis |
| Left / right piezo | A sensor disc with vibration arcs on its own side |
| Pace | A metronome |
| Pitch variation | An irregular zigzag |

`FonosIcon` scales each icon with Dynamic Type. The filled check (`CheckDisc`) and the battery (`BatteryGlyph`) are drawn in SwiftUI, because a template image can't hold a cut-out or a live fill level.

## Screens

**Speak** (opening tab)
1. Toolbar: settings, a status pill (Band ready / Listening / Translating / Speaking), band battery.
2. The Fold view card.
3. The latest translated phrase in Title 2 with a 52 pt "Say it again" button and its clarity score. While listening, the words appear as they are recognized.
4. The **Speak button**: 132 pt, centered. Tap to listen, tap again (or pause) to finish. It never requires holding. Teal when idle, red while listening, sky while translating or speaking.
5. Quick phrases in a two-column grid of 60 pt buttons. One tap speaks the phrase.
6. "Said today": earlier phrases, each tappable to say again.

**Progress**
1. Week / Month / 3 Months segmented control.
2. Clarity, Strength, and Pace rings; each opens its detail.
3. Insight card: the most notable change since baseline across all measures, explained gently, with the baseline date.
4. Weekly speech check card: "Your check is due" with a 54 pt Start check button, or when the next check is due with a secondary "Do a check now".
5. Voice-banking card, shown once an articulation or rhythm measure trends lower, and hidden once dismissed or once a Personal Voice exists. "How to do it" expands three plain steps for iPhone's Personal Voice.
6. Sample-data notice.
7. Four sections, one per speech system (Breathing, Voice, Articulation, Rhythm and intelligibility), each with Apple Health–style cards that say whether the values come from conversation or the weekly check.
8. Days with sessions in the last week.

**Measure detail** (one screen for every measure): the average (or the tapped day's value), the trend against baseline, a line chart with a dashed baseline rule and drag-to-inspect (check measures show a point per check and default to 3 months), then what the measure means, how it's measured, and its speech system, plus a reminder that Fonos does not diagnose.

**Speech check** (full-screen cover): intro listing the four tasks and tips for comparable results, then one screen per task with the instruction in Title 3, a "Read instructions aloud" button, a 60 pt Start button, and "Skip this task". While recording, a live level bar, a timer (or countdown for the 6 s tasks), and a Done button for tasks that end with the voice. After each task, the headline number or a plain "couldn't measure that one" with Try again. Then a results screen grouped by speech system that compares with last week in neutral words. Taps in the first 0.8 s after a step changes are ignored, so a double tap or tremor can't skip a task with the button that took the previous one's place. Quitting asks for confirmation.

**Band**: device card with battery and a pause/resume control, a notice that the band is simulated, one card per sensor with a live trace and contact state, and a live left/right balance bar.

**Settings** (sheet): voice and Personal Voice, speaking speed, test voice; when listening stops (I tap Done, 2, 3, or 5 s) and whether to speak automatically; edit, reorder, and restore quick phrases; appearance; and an About section that states the data source.

## Accessibility

- **Targets.** The Speak button is 132 pt and quick phrases are 60 pt tall. Nothing is smaller than 44 pt.
- **No precise gestures.** Every action is a single tap. Nothing requires holding, swiping, or timing.
- **Dynamic Type.** All text uses text styles. At accessibility sizes the Speak button moves to the top of the screen so it stays in the first viewport, and the chart legend wraps under its title.
- **VoiceOver.** The Fold view reads out the live left/right balance. Rings and cards are single elements with a label and value. Starting to listen posts a "Listening" announcement.
- **Reduce Motion.** Ring fills, the listening pulse, and the status-pill pulse stop animating, and live charts redraw at 10 fps instead of 30.
- **Large text on Progress.** At accessibility sizes, the three rings become full-width rows so their labels never split mid-word, and ring numerals stop growing at xxxLarge to stay inside the ring.
- **Haptics** confirm each change of Speak state.
- **Honesty.** Numbers are compared with the patient's own baseline, changes under 5% are called steady, and every view of toy data says so.

## Performance

Live charts are the only continuous work, so they are built to cost nothing when unseen:

- Each live view (`FoldView`, `StreamTrace`) pauses its `TimelineView` when it is off screen or the app is inactive. Tabs in a `TabView` stay alive, so without this, hidden charts kept redrawing.
- Views read only the buffers they draw (`StreamStore.fold()` and `trace(_:seconds:)`), instead of copying all six buffers every frame.
- Values that change 10 times a second (mic level, left/right balance) live in small subviews, so only they re-render, not the whole Band screen.
- Paths are decimated to about one point per screen point, and the pitch tracker stops at the first strong peak without allocating.

Measured on a Release build in the iPhone 17 Pro simulator: Speak about 10% CPU, Band about 16%, Progress about 2%. With the Debug baseline before these changes, Progress was at 19% because hidden charts kept drawing.

## Clinic summary (PDF export)

A two-page US Letter report for the care team, generated on the phone (`Fonos/Report`). It is written in a clinical result-sheet register, not the app's dark look: white page, near-black ink, hairline rules, tabular numerals, and one teal accent for trend lines. Status is stated in words ("Stable", "Favorable", "Unfavorable", "Too few data"), with unfavorable rows in bold brick red, so the page still reads in black-and-white print or fax.

**Page 1:** header (period, generated time, report ID) · patient, date of birth, baseline (sessions and checks), period · sample-data notice while data is synthetic · summary naming the affected speech systems · measures table grouped by speech system, with a note on what n and change mean · non-diagnostic statement.

**Page 2:** running header (patient, period, report ID) · a small trend chart for each of the 14 measures, four across (sessions or checks, fitted slope, baseline) · data quality (sessions, coverage, weekly checks, tasks recorded) · methods for every measure and the check tasks · non-diagnostic statement.

**Statistics** (`ClinicReport.swift`):

- **Period** runs from the last time a summary was shared to now. The first summary covers all sessions. The export is only recorded when the share sheet reports success.
- **Change** compares the period mean with the baseline (mean of the first 5 sessions, or of the first 3 weekly checks). Within ±5% is "Stable"; reading fatigue uses an absolute difference with a 1 dB band.
- **Slope** is an ordinary least-squares fit of values on time, scaled to 30 days, with a 95% confidence interval from Student's t. It needs 3 values spanning at least 7 days.
- **Status** needs at least 3 values in the period.

**Export screen:** a live preview of the exact page, what the period covers, optional name and date of birth (blank fields print as lines the clinic can fill in), and one 60 pt Share button. Patient details are stored on the phone only.
