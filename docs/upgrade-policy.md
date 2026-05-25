# Upgrade policy

## What kmp-forge does over a project's lifetime

`kmp-forge` is **greenfield-focused**: it scaffolds a new project once via `/kmp-forge-init`, then assists *ongoing feature work* via slash commands and agents.

It does **not** retroactively migrate existing scaffolded projects to match a newer plugin version. This is a deliberate trade-off — full migration tooling would require diff-tracking every template change across plugin versions and produce brittle, hard-to-review changes in user projects.

## What you get automatically

- `/kmp-forge-bump-stack` — refreshes `libs.versions.toml` against latest stable lib versions. Reviewer sees the diff before commit.
- `/kmp-forge-add-feature`, `/kmp-forge-add-screen`, `/kmp-forge-add-platform`, `/kmp-forge-add-library`, `/kmp-forge-add-module` — keep producing modern, current overlay-style outputs as the plugin evolves.
- `kmp-reviewer` agent — applies the **latest** rules in the plugin to your diffs, even if your scaffold structure is older.

## What requires manual work

- **Structural changes to scaffolded modules** (e.g. plugin v2 splits `:domain` into `:domain` + `:domain-core`): you migrate by hand. Plugin docs link to a migration note in `CHANGELOG.md` for each breaking template change.
- **CI workflow updates**: when `pr.yml` or `release.yml` gets new steps in a plugin update, you manually copy the updated workflow from the plugin repo's `overlay/ci/` directory.
- **CLAUDE.md template updates**: similarly, manually copy diff from `overlay/root/CLAUDE.md.tmpl` if you want the latest section structure.

## Versioning the plugin

[SemVer](https://semver.org/spec/v2.0.0.html):

- **Major**: breaking template or structural change (e.g. dropping a locked-stack lib, renaming overlay modules, changing CLAUDE.md template shape in a non-additive way)
- **Minor**: new commands, new skills, new templates, additive doc changes
- **Patch**: doc fixes, intra-version library bumps in `libs.versions.toml.tmpl`, bug fixes in scripts

Plugin's `CHANGELOG.md` notes which template changes affect existing projects.

## When to consider migrating an existing project

Heuristic: if the gap between your scaffold and current plugin templates is creating real friction (CI is using outdated actions, your CLAUDE.md is missing useful sections, your library catalog drifted), schedule an "infra refresh" PR:

1. `git checkout -b chore/kmp-forge-refresh`
2. Read `kmp-forge/CHANGELOG.md` for everything since your scaffold version
3. Apply changes selectively from `kmp-forge/overlay/` and `kmp-forge/docs/` URLs
4. Run `/kmp-forge-bump-stack`
5. Run `kmp-reviewer` over the diff for cleanup
6. Merge as a single chore PR

Plan ~1 hour per ~6 months of plugin drift. Don't try to keep continuously current — projects are good enough as long as builds are green and Claude has the docs it needs.

## Why no automated migration in v1

- Templates are diverse (Gradle, YAML, Markdown, Kotlin) — no one renderer covers them
- Users hand-edit files post-scaffold, so any blind overwrite is destructive
- Migration *tooling* would need a model of "what's still original" vs "what the user changed"
- Maintenance burden compounds: every plugin release has to ship migration logic against every prior release

If migration demand grows post-v1 (multiple personal projects, real friction), v2 can add `/kmp-forge-migrate <from-version> <to-version>` with conservative behavior: only patch files matching the prior template byte-for-byte, surface conflicts as PR comments rather than auto-resolving.

## Read this before starting a v2 / breaking plugin release

- Bump major version in `.claude-plugin/plugin.json`
- Add `## [v2.0.0] — YYYY-MM-DD` section to `CHANGELOG.md` listing every breaking template change with manual-migration steps
- Update `marketplace.json` in `arthurnagy-claude-plugins` to point to the new tag
- Open a tracking issue in the plugin repo for the migration; link from the README's "Currently supported" badge
