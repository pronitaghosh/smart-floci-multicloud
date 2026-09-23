---
description: Append concise summary of previous prompt to LEARNINGS.md
---

Add FAQ entry to LEARNINGS.md for later reference. User supplies question verbatim.

Steps:
1. Read LEARNINGS.md to find appropriate heading/topic
2. Use user-provided prompt as `Q:` verbatim (FAQ question)
3. Write `A:` concise, factual, minimal words: what, why, file:line refs; no narrative
4. Add metadata: date `YYYY-MM-DD`, category/tag, related commits/files
5. Append under heading `## YYYY-MM-DD - <topic>` or existing topic heading in LEARNINGS.md
6. Use edit tool to update LEARNINGS.md

Rules:
- Q is manual prompt verbatim for future search/read
- A is developer explanation with file:line refs and commit SHAs where applicable
- Keep FAQ searchable: use `Q:` prefix, include keywords

$ARGUMENTS
