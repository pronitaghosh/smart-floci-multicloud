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

## Floci docs

When asked to read floci documents, refer to https://floci.io/floci-gcp/services/.

## Implementation control

- User `pause` stops phased work immediately, enters interactive questions mode.
- User `resume` continues from last checkpoint, no repeat.
- While paused: no applies, no file changes, no emulator changes unless user requests.
- Every shell command carries why plus expected output before it runs.
- Terraform: run `plan -out` to a file for user review before any `apply`. Apply uses the reviewed plan file.
- GCP stack verification: use `helper-pg/verify-tf-stack.sh <stack-dir> full` for init, validate, plan; `apply` only the reviewed plan file.

## QA worktree

- QA work happens in `.worktree/gcp-qa` (detached at `gcp` tip); impl stays in main checkout.
- Impl agents do not interact with the QA agent unless the user mentions it.
- Impl agents do not run tests in the workspace (`gcp` branch); QA owns all test runs.
- Same rules bind QA agents: no commit/push/tags without explicit user confirmation; pause/resume, plan-out review, Thought lines, and question-on-doubt apply equally.
- Guide and update target: main `docs/gcp-floci-tests-plan.md` and `docs/gcp-tests-journal.md`; worktree stays code-only.
- Tests need main state: override `STATE_ROOT` to main checkout `.state/dev/gcp`; emulator and cluster are shared.
- Run suite from worktree with main venv: `<main>/floci-pyenv/bin/python -m pytest tests/gcp -q`.

## DEV worktree

- DEV workspace is bound to branch `gcp` only; no work on other branches.
- DEV and QA agents treat each other as fellows: neither crosses into the other's worktree or scope.
- Neither DEV nor QA interacts with the other unless the user specifically mentions it; if needed, one must ask the user before interacting.

## Learning session

- This is a learning session. User asks to understand what agent does and why.
- Each agent response ends with one `Thought:` line: goal, why, next.
- Each block journal entry includes one `Thought:` line.
- Add agent responses to `docs/LEARNINGS-GCP-FLOCI.md` only when user explicitly requests.
