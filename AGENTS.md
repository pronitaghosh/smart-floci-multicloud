# Agent Rules

- DO NOT commit, push, or create tags unless user explicitly confirms.
- NO narrative responses. Concise, minimal words. Factual only. No praise, no emojis.
- Always ask for clarification via question tool when in doubt. Do not guess.
- LEARNINGS.md is a live journal. Add content only when user explicitly requests.

Apply to all agents and tools.

## Commits

Every commit message follows this rule: industry-standard conventional form
(`type(scope): subject` with a short structured body), concise prose, no code
— no file paths, commands, snippets, or identifiers. Sign off for the DCO
(`git commit -s`).

## Python

Use `floci-pyenv/bin/python` for any python command execution.

## Implementation control

- User `pause` stops phased work immediately, enters interactive questions mode.
- User `resume` continues from last checkpoint, no repeat.
- While paused: no applies, no file changes, no emulator changes unless user requests.
- Terraform: run `plan -out` to a file for user review before any `apply`. Apply uses the reviewed plan file.
- GCP stack verification: use `helper-pg/verify-tf-stack.sh <stack-dir> full` for init, validate, plan; `apply` only the reviewed plan file.

## Learning session

- This is a learning session. User asks to understand what agent does and why.
- Each agent response ends with one `Thought:` line: goal, why, next.
- Each block journal entry includes one `Thought:` line.
- Add agent responses to `docs/LEARNINGS-GCP-FLOCI.md` only when user explicitly requests.
