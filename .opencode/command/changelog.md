---
description: Update CHANGELOG.md with newer changes since last entry
---

Update CHANGELOG.md with newer changes.

Steps:
1. Read CHANGELOG.md and determine last entry date/commit
2. Run `git log --oneline --since="<last date>"` and `git diff --stat HEAD` to collect changes
3. Summarize changes concisely, minimal words, factual, with commit SHAs and file:line refs
4. Append new section `## [<short-sha>] - YYYY-MM-DD HH:MM UTC - <summary>` to CHANGELOG.md
5. Use edit tool to update file

Rules:
- Do not repeat git commit description verbatim; rewrite as developer change explanation
- Explain: what changed, why required, how validated; optionally alternatives considered, issues faced
- Add categorization for blast radius / type to aid production deployment decision (e.g., `infra`, `config`, `k8s`, `docs`, `tooling`, `breaking`, `low/medium/high risk`)

$ARGUMENTS
