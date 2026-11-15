# LLM feedback

How Fonos turns a take's measurements into coaching with Claude: the architecture, the request, the prompt, the input payload, the output schema, a worked example, and the guardrails.

## 1. Architecture

```
iPhone (on-device analysis)
  │  metrics JSON only, HTTPS, App Attest token
  ▼
Fonos feedback server (stateless)
  │  validates payload, builds request, holds the API key
  ▼
Claude Messages API (claude-opus-5-5)
  │  structured JSON
  ▼
Feedback server validates the JSON against the schema
  ▼
iPhone renders the feedback card
```

- **Why a server:** the Anthropic API key must never ship inside the app. The server also validates input, enforces rate limits, and strips anything the schema doesn't allow.
- **Local first:** the app's `LocalCoach` produces a rule-based card instantly in the same JSON shape. The LLM card replaces it when it arrives, usually within about 3 s. With no network or with feedback off, the local card is the result.

## 2. Request (Claude Messages API)

Request body the server sends to `POST /v1/messages` (shown as the raw JSON shape; the server uses the official Anthropic SDK for its language):

```json
{
  "model": "claude-opus-5-5",
  "max_tokens": 2048,
  "fallbacks": "default",
  "output_config": {
    "effort": "low",
    "format": { "type": "json_schema", "schema": "<FEEDBACK_SCHEMA, section 5>" }
  },
  "system": [
    {
      "type": "text",
      "text": "<SYSTEM_PROMPT, section 3>",
      "cache_control": { "type": "ephemeral" }
    }
  ],
  "messages": [
    { "role": "user", "content": "<TAKE_PAYLOAD as JSON text, section 4>" }
  ]
}
```

Header: `anthropic-beta: server-side-fallback-2026-07-01`

- **Model:** `claude-opus-5-5`, the current default Claude model.
- **Effort:** `low`. Feedback is short and latency matters more than deep reasoning. (On Opus 5.5 thinking can't be turned off; effort is the control. Its default is `medium`, so set `low` explicitly.)
- **Structured output:** `output_config.format` guarantees JSON matching the schema, so the app never parses free text.
- **`max_tokens` 2048:** the output is a short JSON object. The cap leaves headroom so the JSON is never cut off.
- **Refusal fallback:** `fallbacks: "default"` with the beta header lets Anthropic re-run a declined request on a fallback model server-side. Even so, the server checks `stop_reason`: on `"refusal"` or `"max_tokens"` it returns the local card instead.
- **Prompt caching:** the system prompt (role, rules, glossary, drill library) is identical on every request and comes first, marked with `cache_control`. The per-take payload comes after it. Opus 5.5 caches prefixes of at least 512 tokens, and the system prompt is well above that. Confirm hits with `usage.cache_read_input_tokens` in server metrics; anything that varies (timestamps, IDs) must stay out of the system prompt.
- **Errors:** retry once on 429/5xx with backoff, then fall back to the local card. A 4xx is a bug: log the status only, never the payload.

## 3. System prompt (cached)

```text
You are Fonos, a warm, precise singing coach. A singer has just finished one take
of an exercise. You receive measurements computed on their phone from a throat-band
microphone and two throat accelerometers (left and right of the larynx). You never
hear the audio. Write feedback for this take.

Rules
1. Use only the numbers in the payload. Never invent measurements, notes, or history.
2. Give exactly one focus: the change most likely to improve the next take. Prefer
   pitch accuracy, then steadiness, then onsets, then everything else, unless a
   metric is far outside the singer's own baseline.
3. Mention at most two wins, and only real ones (at or better than baseline, or in
   the "good" band).
4. Pick the drill from the drill library below. Do not invent drills.
5. If signal_quality.overall is "low", or a metric is marked unreliable, do not
   coach on it. Say briefly what to fix (for example, band fit or room noise) and
   set confidence to "low".
6. Metrics marked status "exploratory" may appear only as a neutral observation,
   never as the focus.
7. Never diagnose, mention medical conditions, or suggest anything is wrong with
   the singer's health. If strain-related metrics are high, suggest rest, water, and
   an easier range, nothing more.
8. Coaching level "beginner": plain words, no jargon, no cents values; use "a little
   flat", "wobbly", "breathy start". Leave technical_note null.
   Coaching level "technical": you may use cents, Hz, onset types, passaggio, HNR,
   and singer's formant, and you fill technical_note with one or two sentences.
9. Lengths: headline up to 60 characters. Summary one or two sentences. Each
   observation one sentence. Drill steps: 2 to 4 short imperative steps.
10. Encouraging, never gushing. No exclamation marks in a row. Never shame.

Metric glossary (name: meaning; better direction; typical good band)
- pitch_accuracy_pct: share of voiced time within ±25 cents of target; higher; ≥80 good
- mean_pitch_error_cents: signed average deviation (negative = flat); nearer 0; |x|≤10 good
- sustain_stability_cents: pitch wobble on held notes, vibrato removed; lower; ≤12 good
- onset_settle_ms: time to land the note; lower; ≤150 good
- onset_excursion_cents: scoop (negative) or overshoot (positive) at onset; nearer 0
- vibrato_rate_hz: vibrato speed; ~5–7 typical for classical; n/a if no vibrato
- vibrato_extent_cents: vibrato width; ~±30–100 typical when present
- vibrato_regularity_pct: cycle-to-cycle variation; lower; ≤15 even
- dynamic_range_db: loud-to-soft range; context dependent
- sustain_level_sd_db: volume wobble on held notes; lower; ≤2 steady
- phrase_duration_s: longest voiced phrase
- hnr_db: clear (higher) vs breathy (lower) tone
- singers_formant_db: "ring"; higher is more ring
- throat_vibration_pct_baseline: neck vibration vs the singer's baseline
- lr_symmetry_pct: left/right vibration balance; mostly band fit; ≥85 good
- vibration_to_sound_ratio_vs_baseline: >1.2 may mean extra effort (exploratory)
- onset_type: "balanced", "hard", or "breathy" (exploratory)
- larynx_rise_vs_speaking: larynx height change vs speaking baseline (exploratory)

Drill library (id: name — use for)
- lip_trill_slide: Lip-trill slides — steadiness, easy onsets, effort
- hum_to_vowel: Hum to "ah" on one note — onsets, tone, ring
- five_note_slow: Slow five-note scale with a drone — pitch accuracy
- target_and_hold: Land, then hold for four counts — onset settling, sustain stability
- messa_di_voce: Soft–loud–soft on one note — dynamic control, sustain level
- straw_phonation: Sing through a straw — effort, larynx rise, breathiness
- staccato_ah: Light staccato "ha" — hard onsets, breathiness
- sirens_easy: Gentle sirens on "ng" — range, register shifts, larynx rise
- breath_four_count: Four-count breath, then sustain — phrase duration
- speak_then_sing: Speak the line, then sing it on the speaking pitch — speech-to-singing transition
```

## 4. Take payload (per request, not cached)

```json
{
  "coaching_level": "beginner",
  "singer": {
    "voice_type": "not_sure",
    "goals": ["in_tune", "steadier"],
    "range": { "low": "A2", "high": "E4" }
  },
  "exercise": {
    "id": "five_note_scale",
    "key": "D3",
    "pattern": ["D3", "E3", "F#3", "G3", "A3", "G3", "F#3", "E3", "D3"],
    "duration_s": 11.4,
    "take_number": 3
  },
  "signal_quality": {
    "overall": "good",
    "left_contact": true,
    "right_contact": true,
    "mic_accel_pitch_agreement_pct": 94,
    "room_noise_dbfs": -58,
    "clipping": false
  },
  "metrics": {
    "pitch_accuracy_pct":      { "value": 71, "baseline": 66, "trend_4w": "up",   "status": "established" },
    "mean_pitch_error_cents":  { "value": -14, "baseline": -18, "trend_4w": "up",  "status": "established" },
    "sustain_stability_cents": { "value": 11, "baseline": 13, "trend_4w": "flat", "status": "established" },
    "onset_settle_ms":         { "value": 230, "baseline": 210, "trend_4w": "flat", "status": "established" },
    "onset_excursion_cents":   { "value": -38, "baseline": -30, "trend_4w": "flat", "status": "established" },
    "lr_symmetry_pct":         { "value": 92, "baseline": 91, "trend_4w": "flat", "status": "exploratory" },
    "onset_type":              { "value": "breathy", "status": "exploratory" }
  },
  "worst_notes": [
    { "note": "F#3", "pitch_error_cents": -31, "settle_ms": 310 },
    { "note": "A3",  "pitch_error_cents": -22, "settle_ms": 260 }
  ]
}
```

Payload rules:

- Values are rounded: integers for cents, %, and ms; one decimal for s, Hz, and dB.
- Only metrics relevant to the exercise are included (no vibrato on a staccato drill).
- No timestamps, names, device identifiers, or audio-derived text are ever included.
- `goals` is included only if the singer turned on "Use my goals in feedback".

## 5. Output schema

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["headline", "summary", "wins", "focus", "next_target", "technical_note", "confidence"],
  "properties": {
    "headline": { "type": "string" },
    "summary":  { "type": "string" },
    "wins": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["metric", "observation"],
        "properties": {
          "metric": { "type": "string" },
          "observation": { "type": "string" }
        }
      }
    },
    "focus": {
      "type": "object",
      "additionalProperties": false,
      "required": ["metric", "observation", "why", "drill_id", "drill_steps"],
      "properties": {
        "metric": { "type": "string" },
        "observation": { "type": "string" },
        "why": { "type": "string" },
        "drill_id": {
          "type": "string",
          "enum": ["lip_trill_slide", "hum_to_vowel", "five_note_slow", "target_and_hold", "messa_di_voce",
                   "straw_phonation", "staccato_ah", "sirens_easy", "breath_four_count", "speak_then_sing"]
        },
        "drill_steps": { "type": "array", "items": { "type": "string" } }
      }
    },
    "next_target": {
      "type": "object",
      "additionalProperties": false,
      "required": ["metric", "target", "unit"],
      "properties": {
        "metric": { "type": "string" },
        "target": { "type": "number" },
        "unit": { "type": "string" }
      }
    },
    "technical_note": { "type": ["string", "null"] },
    "confidence": { "type": "string", "enum": ["high", "medium", "low"] }
  }
}
```

The schema format doesn't support numeric or length limits, so the server enforces them after parsing: `wins` gets at most 2 items, `drill_steps` 2–4, and `headline` 60 characters. Out-of-range output is trimmed, never re-requested.

## 6. Sample feedback

For the payload above, at beginner level:

```json
{
  "headline": "More in tune than your usual",
  "summary": "Your scale landed in tune more often than your usual. The notes still start a little low and take a moment to settle, especially the third note.",
  "wins": [
    { "metric": "pitch_accuracy_pct", "observation": "You were in tune 71% of the time, up from your usual 66%." },
    { "metric": "sustain_stability_cents", "observation": "Your held notes were steadier than usual." }
  ],
  "focus": {
    "metric": "onset_excursion_cents",
    "observation": "Most notes start a little below the target and slide up into it.",
    "why": "Landing right on the note makes the whole line sound more in tune.",
    "drill_id": "target_and_hold",
    "drill_steps": [
      "Hum the target note quietly first.",
      "Start the note on the hum's pitch, with no slide.",
      "Hold it for four counts.",
      "Repeat on the third note of the scale."
    ]
  },
  "next_target": { "metric": "onset_settle_ms", "target": 180, "unit": "ms" },
  "technical_note": null,
  "confidence": "high"
}
```

At technical level, the same take adds:

```json
"technical_note": "Onsets average a −38 cent scoop with 230 ms settling; F#3 is the outlier at −31 cents and 310 ms. The accelerometer onset reads breathy (exploratory), consistent with airflow preceding fold closure."
```

## 7. Rendering in the app

| JSON field | Feedback card |
|---|---|
| `headline` | Title, Sora semibold |
| `summary` | Body text, Atkinson Hyperlegible Next |
| `wins` | Up to two rows with a check disc and the metric's icon |
| `focus` | The main card: observation, "Why it matters", drill name and steps, **Try the drill** button |
| `next_target` | "Next time: aim for 180 ms" with the metric's ring |
| `technical_note` | Collapsible "Technical detail" row, shown only at technical level |
| `confidence: "low"` | An inline notice above the focus: "Signal was weak this take, so feedback is limited." |

## 8. Quality checks before launch

- **Eval set:** 100+ synthetic and consented real takes covering every exercise, both coaching levels, and low-quality signals. Grade each output for:
  - every number traced to the payload
  - exactly one focus
  - a drill ID from the library
  - no medical language
  - jargon only at technical level
- **Regression:** rerun the eval on any prompt, schema, or model change; compare the pass rate.
- **Monitoring:** cache hit rate, latency p50/p95, refusal and fallback counts, and the local-card fallback rate. Track counts only, never payloads.
