---
name: mvp-spec-authoring
description: Author docs/MVP_SPEC.md for a kmp-forge project — interactive interview structure, section templates, and what makes a spec good vs vague. Used by the /kmp-forge-spec command.
---

# MVP Spec authoring

`docs/MVP_SPEC.md` is the single source of truth for product scope in a kmp-forge project. Claude reads it on every session for context. It should be short enough to scan in 60 seconds, specific enough that someone could ship v1 from it alone.

## Structure (in this order)

1. **Overview** — one paragraph
2. **Target users** — one paragraph
3. **Business model** — one line
4. **Must-have (v1)** — bullets, user-terms
5. **Out of scope (v1)** — bullets
6. **Key user flows** — 2–4 flows, each 3–6 steps
7. **Critical technical considerations** — bullets
8. **Success metrics** — bullets

## Section-by-section guidance

### Overview

A paragraph that answers: what does the app do? what user problem does it solve? what's the wedge?

✓ "MyApp adds aesthetic borders to photos so they fit social media aspect ratios (1:1, 4:5, 9:16) without losing original composition. Photographers shooting on real cameras get a 30-second batch tool instead of having to crop manually in Lightroom."

✗ "MyApp is a photo app." (too vague)
✗ "MyApp uses Kotlin Multiplatform with Compose for a native-quality experience..." (technical, not product)

### Target users

One paragraph describing the *primary* persona. Add secondary personas only if they meaningfully change scope.

✓ "Hobbyist photographers who shoot on mirrorless or DSLR cameras and post to Instagram/TikTok. They care about composition; they refuse to crop. They edit in Lightroom and want a fast way to add borders before sharing."

✗ "Anyone with a camera." (no boundaries → no decisions)

### Business model

One line. Mention price points if known.

✓ "Freemium with one-time premium unlock ($4.99–$9.99). Free tier: 4 images/batch + ads. Premium: unlimited + color palettes + gradients."

✗ "Maybe subscription, maybe one-time, TBD."

### Must-have (v1)

3–10 bullets, in user terms. Each describes a capability the user gets.

✓ Multi-image selection (batch editing)
✓ Aspect ratio presets (1:1, 4:5, 9:16) + custom
✓ Frame customization: solid colors, gradients
✓ Export processed images to gallery
✓ Free tier: 4-image limit, ads after export

✗ "Use Coroutines for async" (technical)
✗ "Have a good UI" (vague)

### Out of scope (v1)

Equally important — what you're explicitly NOT building. Prevents scope creep.

✓ Photo filters / adjustments
✓ Text or sticker overlays
✓ Cloud sync
✓ Subscription model

### Key user flows

For each flow, 3–6 numbered steps. Cover the golden path; mention edge cases briefly only if they shape v1 scope.

```
### Flow 1: First batch export
1. User opens the app.
2. Taps "New batch" — system photo picker opens.
3. Selects up to 4 images (free tier).
4. Frame editor: picks aspect ratio + frame color.
5. Preview grid shows all processed images.
6. Taps Export — saves to gallery, shows ad, returns to home.
```

### Critical technical considerations

Non-obvious constraints that shape architecture or scope. Examples:

✓ "Batch processing target: <30s for 4 images of 24MP"
✓ "Offline-only — no backend in v1"
✓ "Image processing must not block UI thread"
✓ "Must run on Android API 24+"

✗ "Use clean architecture" (architectural opinion, lives in ADRs)
✗ "Performant code" (no decision content)

### Success metrics

How will you know v1 succeeded? Pick 2–4 specific metrics.

✓ "Day-7 retention ≥ 30% (industry baseline ~25%)"
✓ "Free→Premium conversion ≥ 3% within 14 days"
✓ "App Store rating ≥ 4.4 after first 500 reviews"

✗ "Users love it" (unmeasurable)

## What makes a good spec

- **Decisions, not aspirations**. "Multi-image batch" not "support multiple images somehow."
- **User-language**, not implementation. Save the implementation language for ADRs and architecture docs.
- **Explicit out-of-scope**. Says what you're NOT building. Prevents scope creep more than what you ARE building.
- **Specific metrics** for success.
- **Short**. If it's >2 pages, you're hiding decisions in prose.

## What goes elsewhere (not in MVP_SPEC)

- Architecture / module layout → `docs/architecture.md` (plugin) + per-project ADRs
- Stack choices and rationale → `docs/DECISIONS/*.md`
- Roadmap / phases → `docs/ROADMAP.md` (optional, per-project)
- Detailed wireframes → Figma (linked from `CLAUDE.md`)
- Competitor analysis → `docs/COMPETITOR_ANALYSIS.md` (optional, per-project)

## /kmp-forge-spec modes

The `/kmp-forge-spec` command supports:

- **Default (interview)**: walk section-by-section, asking each via `AskUserQuestion`. Push back briefly on vague answers.
- **`--from-dump`**: user pastes a free-form product idea; the command extracts what maps to spec sections and asks follow-ups only on gaps.

Both modes write to `docs/MVP_SPEC.md` using the template at `overlay/product/MVP_SPEC.md.tmpl`.

## Maintaining the spec

Treat updates as substantive — commit as `docs: refine MVP spec` (or `docs: expand MVP scope`). Major scope shifts get a `docs: pivot to ...` commit + an ADR explaining the why.

Don't let MVP_SPEC.md decay into a wishlist. If a feature has been "in must-have" for 6+ months without shipping, move it to a `docs/ROADMAP.md` phase instead.
