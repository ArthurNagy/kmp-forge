---
description: Author docs/MVP_SPEC.md interactively or by structuring a free-form dump.
argument-hint: "[--from-dump]"
---

# /kmp-forge-spec

Generates or revises `docs/MVP_SPEC.md` for a kmp-forge project.

First load the `kmp-forge:mvp-spec-authoring` skill (Skill tool; where it isn't available, read
`${CLAUDE_PLUGIN_ROOT}/skills/mvp-spec-authoring/SKILL.md`) — it holds the section templates and the good-vs-vague
checklist this command applies.

If `docs/MVP_SPEC.md` already has content, ask via `AskUserQuestion` first: **Revise sections (Recommended)** ·
**Start over** — never overwrite it without that answer.

## Modes

Arguments: `$ARGUMENTS` (`--from-dump` selects the second mode).

### Default — interactive interview

Ask each section's question as a plain message and wait for the answer (the answers are free text). Use
`AskUserQuestion` only where the choices are fixed — **Business model**: Freemium · One-time · Subscription · Free
with ads. Cover the full MVP_SPEC template structure:

1. **Overview** — one paragraph: what the app does, the problem it solves
2. **Target users** — primary persona; one paragraph
3. **Business model** — freemium / one-time / subscription / free with ads / etc
4. **Must-have features (v1)** — bulleted, user-terms (not technical)
5. **Out of scope (v1)** — explicitly deferred features
6. **Key user flows** — at least 2 flows, each 3–6 steps
7. **Critical technical considerations** — performance budget, memory, offline support, etc
8. **Success metrics** — activation, retention, NPS target

For each section, after the user answers:
- Push back briefly if the answer is vague ("could you name 2-3 specific must-have features?")
- Accept the answer when concrete
- Write it into the corresponding section of `docs/MVP_SPEC.md`

### --from-dump — structure a free-form paste

If invoked with `--from-dump`: any text after the flag is the dump. Otherwise ask for it in a plain message and end
your turn:

> Paste your product idea, vision, or any context you have. I'll structure it into the MVP_SPEC template and ask follow-up questions on gaps.

Read the dump, extract sections that map to MVP_SPEC structure, write them in, then ask follow-up questions only for sections that are empty or vague.

## Output

Overwrite or update `docs/MVP_SPEC.md` based on the template in `${CLAUDE_PLUGIN_ROOT}/overlay/product/MVP_SPEC.md.tmpl`.

Substitute:
- `${APP_NAME}` — already in CLAUDE.md
- `${APP_TAGLINE}` — derive from Overview if not set

## After writing

- Surface the resulting `docs/MVP_SPEC.md` for the user to review
- Suggest a Conventional Commit:
  ```
  docs: author MVP spec
  ```
- Suggest the user also update CLAUDE.md's `One-liner` field to match the spec's tagline (use Edit tool)
- Suggest `/kmp-forge-refine --gaps` next: the product-owner agent drafts the first backlog issues from the spec's Must-haves and flows (the user approves them with the `ready` label)

## Notes

- Don't write a ROADMAP.md by default — user opts in if/when they want one.
- This command is most useful at project start. Rerunning later updates the spec; treat updates as substantive (commit as `docs: refine MVP spec`).
