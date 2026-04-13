---
applyTo: "**/*.md"
---

# Markdown Governance Instructions

These instructions apply whenever any `.md` file is created or modified.

## Non-Negotiable: Zero Problems Tab Issues

The VS Code Problems tab **must be empty** after every markdown edit. No lint
errors, no warnings, no info messages — not even in documentation files.

### Before committing any markdown change, run

```powershell
cd D:\Footwear
markdownlint "**/*.md" --ignore node_modules --ignore "app/build" --ignore "functions/node_modules"
```

**Expected output: nothing (exit 0).** Any output is a blocker.

---

## Enforced Rules (`.markdownlint.json`)

1. **MD022** — Always add a blank line before AND after every heading.
2. **MD024** (`siblings_only`) — Duplicate heading text is OK in different
   parent sections (e.g., multiple `### Added` in CHANGELOG across versions).
3. **MD031** — Blank line before/after fenced code blocks.
4. **MD032** — Blank line before/after bullet/numbered lists.
5. **MD040** — Every fenced code block must declare a language (`bash`, `dart`,
   `json`, `powershell`, `text`, etc.).

---

## Prohibited in Committed Markdown

Never reference these in any tracked `.md` file:

- Temp log files: `debug.log`, `app_logs.txt`, `device_logs_*.txt`,
  `fresh_errors.txt`, `fresh_logs.txt`, `logs_live.txt`
- Dev scripts: `check_locale.ps1`, `check_locale.py`
- Auth exports: `auth-users.json`
- Local installer artifacts: `installer_done.flag`, `*.flag`
- Session-internal working notes that don't belong in permanent governance

These belong strictly in `.gitignore`.

---

## Auto-Fix for Bulk Issues

```powershell
markdownlint --fix "path/to/file.md"
markdownlint "path/to/file.md"   # verify zero issues remain
```

---

## Governance Docs Are Permanent

The following docs are critical governance artifacts — **never delete them**:

`AGENTS.md`, `CLAUDE.md`, `README.md`, `app/README.md`,
`CHANGELOG.md`, `REGRESSION_REGISTRY.md`, `MASTER_BLUEPRINT.md`,
`AUDIT_REPORT_FOOTWEAR_ERP.md`, `SESSION_LOG.md`,
`.claude/CLAUDE.md`, `.claude/skills/*/SKILL.md`

---

## Load the Full Skill for Complex Edits

When creating a new governance doc or skill file, load:
`.claude/skills/markdown-governance/SKILL.md`
