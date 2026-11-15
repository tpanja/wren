---
version: 1
slug: "fonos-report"
primary_target: "Fonos/Report"
related_targets: ["Fonos/Features/Report"]
---

# Clinic summary report (one-page PDF export)

Mode: Read. A printed or emailed document a neurologist or speech-language pathologist reads in under a minute, alongside the clinic chart. Code-led.

Audience and job: the clinician interprets trends between visits; the patient only generates and shares it. Report period = since the last shared summary (first export: all sessions). Optional patient name and date of birth, stored on the phone only; blank lines print when empty.

Content: header (Wren, title, period, generated date, report ID), patient block, sample-data notice while data is synthetic, one-sentence summary, measures table (baseline, period mean, change vs baseline, slope per 30 days with 95% CI, status against the ±5% band), six small trend charts, data-quality block (sessions, active days, voiced minutes, piezo and translator coverage, longest gap), methods footnotes and a non-diagnostic statement.

## Direction contract

THESIS: A lab-report register, not an app screenshot. The page reads like a clinical result sheet: ruled tables, tabular numerals, one accent, status words rather than colour alone. It refuses dashboard rings, cards, and brand decoration.

OWN-WORLD: White paper, near-black ink #14181B, secondary ink #4A545C, hairline rules 0.5 pt #C9CED3, one accent teal #0A7C6E for trend lines and the header rule; unfavourable status in muted brick #9A3B2E with a bold word. Atkinson Hyperlegible Next for text, Sora for the title and numerals.

STORY: In under a minute the clinician knows the period, how much data backs it, which measures moved beyond the steady band and in which direction, and how fast.

FIRST VIEWPORT: The whole US Letter page: header rule and title band at top; patient and period block; summary sentence; the measures table as the page's centre of gravity; a 3x2 grid of small trend charts; data-quality and methods blocks in two columns at the foot; disclaimer line last.

FORM: Pinned by the brief ("professional medical-like report"). Signature move: each table row's status is stated in words and backed by its own small chart below with baseline and fitted slope. seed: none (pinned by brief)

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
