---
name: markdown-governance
description: "Use when: creating, editing, or reviewing any .md file in the ShoesERP repository. This skill enforces markdownlint compliance, canonical doc structure, and prevents Problems-tab regressions. Also use when the Problems tab shows markdown warnings."
applyTo: "**/*.md"
---

# Skill: Markdown Governance

## Zero-Tolerance Policy

The VS Code Problems tab must show **zero** markdown issues at all times.
Every `.md` file created or edited MUST pass the project's
`.markdownlint.json` rules before commit.

**Verify after every edit:**

```powershell
cd D:\Footwear
markdownlint "**/*.md" --ignore node_modules --ignore "app/build" --ignore "functions/node_modules"
# Must exit 0 with no output
```

---

## Active Rule Set (`.markdownlint.json`)

| Rule | Setting | Why |
|------|---------|-----|
| MD013 | disabled | Long lines permitted (tables, code spans) |
| MD022 | enabled | Blank line required before/after every heading |
| MD024 | `siblings_only: true` | Duplicate headings OK in different sections (CHANGELOG pattern) |
| MD031 | enabled | Blank line required before/after fenced code blocks |
| MD032 | enabled | Blank line required before/after bullet lists |
| MD033 | disabled | Raw HTML permitted |
| MD037 | enabled | No spaces inside emphasis markers |
| MD040 | enabled | Fenced code blocks must have language tag |
| MD041 | disabled | First line need not be H1 |
| MD046 | `fenced` | Fenced code style only |
| MD056 | disabled | Table column-count mismatches are not enforced |
| MD060 | disabled | bare URLs permitted |

---

## Common Regressions and Fixes

### MD022 — blank line missing around heading

```markdown
<!-- ❌ WRONG -->
Some text.
### My Heading
- item

<!-- ✅ CORRECT -->
Some text.

### My Heading

- item
```

### MD032 — blank line missing around list

```markdown
<!-- ❌ WRONG -->
Intro sentence:
- item 1
- item 2
Next paragraph.

<!-- ✅ CORRECT -->
Intro sentence:

- item 1
- item 2

Next paragraph.
```

### MD040 — fenced block missing language tag

````markdown
<!-- ❌ WRONG -->
```
flutter build apk --release
```

<!-- ✅ CORRECT -->
```bash
flutter build apk --release
```
````

### MD024 (`siblings_only`) — duplicate heading OK across versions

```markdown
## v3.7.0

### Added   ← OK (different parent)

## v3.6.0

### Added   ← OK (sibling to v3.6.0's Added only)
```

---

## Auto-Fix Workflow

For bulk fixes (new doc, major edits):

```powershell
cd D:\Footwear
markdownlint --fix "path/to/file.md"
markdownlint "path/to/file.md"   # verify zero issues remain
```

`--fix` resolves: MD022, MD023, MD026, MD027, MD030, MD032, MD034, MD037, MD038,
MD039, MD044, MD047, MD049, MD050.

For non-fixable rules (MD040 missing lang tags, MD024 duplicate headings),
you must edit the file manually.

---

## Canonical Document Structures

### Governance Doc (AGENTS.md / CLAUDE.md / SKILL.md pattern)

```markdown
# Title

Last updated: YYYY-MM-DD

## Section 1

Prose paragraph.

### Sub-section

- List item 1
- List item 2

## Section 2
```

### CHANGELOG Entry Pattern

```markdown
## [v3.X.Y+N] — YYYY-MM-DD

### Added

- Feature description

### Changed

- Change description

### Fixed

- Bug fix description
```

### Skill File Pattern

```markdown
---
name: skill-name
description: "Use when: ..."
applyTo: "glob/pattern/**"
---

# Skill: Display Name

## Section

Content.
```

---

## Prohibited Artifacts in Docs

Never reference these in committed `.md` files:

- Temporary file paths (`device_logs_*.txt`, `app_logs.txt`, etc.)
- Local debug logs (`debug.log`, `fresh_errors.txt`)
- Machine-specific paths (`C:\Users\...`, `D:\Footwear\releases\`)
- Session-internal notes that belong in session memory only
- Auth export files (`auth-users.json`)
- Installer flags (`installer_done.flag`, `*.flag`)

These belong in `.gitignore`, not docs.

---

## Pre-Commit Checklist for Markdown

```powershell
# 1. Zero lint issues
markdownlint "**/*.md" --ignore node_modules --ignore "app/build"

# 2. No temp artifact references in committed docs
Select-String -Path "**/*.md" -Pattern "debug\.log|app_logs|device_logs|auth-users\.json|installer_done" -Recurse

# 3. All code blocks have language tags
Select-String -Path "**/*.md" -Pattern "^```$" -Recurse   # should return zero
```

---

## Governance Document Registry

| File | Purpose | Owner | Never delete |
|------|---------|-------|-------------|
| `AGENTS.md` | Runtime contract — roles, rules, collections | All agents | ✅ |
| `CLAUDE.md` | AI coding rules, breakage chains, hard rules | All agents | ✅ |
| `README.md` | Project overview, setup, routes, commands | All | ✅ |
| `app/README.md` | App architecture, provider patterns, screens table | Devs | ✅ |
| `CHANGELOG.md` | Semantic version history | All | ✅ |
| `REGRESSION_REGISTRY.md` | Known regressions with RR-IDs | All agents | ✅ |
| `MASTER_BLUEPRINT.md` | Long-term architecture decisions | Architects | ✅ |
| `AUDIT_REPORT_FOOTWEAR_ERP.md` | Scored audit findings | Audit agents | ✅ |
| `SESSION_LOG.md` | Session-by-session work log | Session agents | ✅ |
| `.claude/CLAUDE.md` | Local mirror/override for .claude/ | Claude agents | ✅ |

**Temporary docs (never commit):**
Already covered by `.gitignore`: `*.txt`, `*.log`, `EMERGENCY_FIXES_*.md`,
`PRODUCTION_SIGNOFF_*.md`, `auth-users.json`, `check_locale.*`,
`installer_done.flag`, `*.flag`.
