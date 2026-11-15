# UI design

## Who it's for

The person living with ALS who wears the band and holds the phone. Their speech is hard for others to understand, and their hand control is declining. Every design decision starts from two facts: being understood is urgent, and effort is expensive.

## Direction

The screenshots supplied for inspiration set the look:

- **From WHOOP:** a dark slate ground, three headline rings with rounded numerals, tracked uppercase card titles, a plain-language insight card, and the weekday check row.
- **From Apple Health:** summary cards with a colored symbol and title, a large value with its unit, and a small trailing bar chart whose last bar carries the color.

**Signature: the Fold view.** On the Speak screen, the contact-mic waveform runs along the midline. The left piezo's vibration rises above it in teal and the right piezo's falls below it in violet, both at the same scale. When both sides vibrate equally the shape is a mirror image; when one side weakens the shape goes lopsided. Symmetry, one of the measures, can be seen without reading a number.

## Color

Each stream and measure keeps its color everywhere it appears.

| Role | Dark | Light |
|---|---|---|
| Ground | `#0F1316` | `#F2F3F5` |
| Card | `#1A2025` | `#FFFFFF` |
| Mic / Strength | `#F2B33D` amber | `#B87700` |
| Left piezo / Clarity / Speak | `#3CC8B4` teal | `#0A8A7A` |
| Right piezo / Symmetry | `#8E7CF0` violet | `#5B48C9` |
| Pace | `#5AA9E6` sky | `#1F6FB2` |
| Listening | `#FF6B5E` | `#C0342B` |

Dark is the default. Settings offers Light and Match iPhone, and every token has a light variant (`Fonos/Design/Theme.swift`).

## Type

SF Pro for interface text and SF Pro Rounded for headline numbers, all on system text styles so Dynamic Type works everywhere. Card titles are small uppercase with wide tracking, as in the WHOOP references.

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
3. Insight card: the most notable change since baseline, explained gently, with the baseline date.
4. Sample-data notice.
5. "All measures": six Apple Health–style cards.
6. Days with sessions in the last week.

**Metric detail**: the average (or the tapped day's value), the trend against baseline, a line chart with a dashed baseline rule and drag-to-inspect, then what the measure means and how it's measured, plus a reminder that Fonos does not diagnose.

**Band**: device card with battery and a pause/resume control, a notice that the band is simulated, one card per sensor with a live trace and contact state, and a live left/right balance bar.

**Settings** (sheet): voice and Personal Voice, speaking speed, test voice; when listening stops (I tap Done, 2, 3, or 5 s) and whether to speak automatically; edit, reorder, and restore quick phrases; appearance; and an About section that states the data source.

## Accessibility

- **Targets.** The Speak button is 132 pt and quick phrases are 60 pt tall. Nothing is smaller than 44 pt.
- **No precise gestures.** Every action is a single tap. Nothing requires holding, swiping, or timing.
- **Dynamic Type.** All text uses text styles. At accessibility sizes the Speak button moves to the top of the screen so it stays in the first viewport, and the chart legend wraps under its title.
- **VoiceOver.** The Fold view reads out the live left/right balance. Rings and cards are single elements with a label and value. Starting to listen posts a "Listening" announcement.
- **Reduce Motion.** Ring fills, the listening pulse, and the status-pill pulse stop animating, and live charts redraw at 10 fps instead of 30.
- **Haptics** confirm each change of Speak state.
- **Honesty.** Numbers are compared with the patient's own baseline, changes under 5% are called steady, and every view of toy data says so.
