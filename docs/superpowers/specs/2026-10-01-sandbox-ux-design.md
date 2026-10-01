# Sandbox UX design — one command, clear roles, guardrails

Date: 2026-10-01. Status: approved in brainstorming, not built. Extends `README.md`; does not
replace its threat model, rules or Phase 7 checks.

## Goal

Make the sandbox usable without memorising raw `docker` commands, so that at every step it is
obvious **who** acts (you or Claude), **where** (Mac terminal, code-server, browser), and what
is not allowed. Mistakes that break isolation should be refused by tooling, not by memory.

Success means:

- Every step of a test has a short Claude phrase and an equivalent `sandbox …` command.
- You can tell at a glance whether a terminal is the Mac or the container.
- Isolation-breaking commands are refused at three layers, and none of them affect normal
  work outside this repo and its containers.

## Decisions

- **Claude runs on the Mac only.** No Claude CLI and no token of any kind inside a container.
  Claude reaches test code only through `sandbox scan`, `sandbox exec` and `sandbox apply`.
- **One command, `bin/sandbox`,** replaces the planned `bin/sandbox-{new,scan,up,export,rm}`.
  The same command serves manual use and Claude.
- **Three guardrail layers**, each scoped so normal work is untouched: a Claude hook in this
  repo (the real boundary), defaults baked into the image, and a zsh wrapper on the Mac that
  only reacts to sandbox names (a guard against mistakes, not attacks).
- **Four indicators:** container prompt, code-server colour, Mac prompt in this repo, Claude
  statusline.

## Components

- `bin/sandbox` — subcommands below. Bash, no dependencies beyond `docker`.
- `boilerplate/Dockerfile` — base image plus prompt, npm/git defaults, code-server colours.
- `.claude/settings.json` + `.claude/hooks/guard.sh` — what Claude may run in this repo.
- `.claude/statusline.sh` — statusline built from `sandbox status --short`.
- `shell/sandbox.zsh` — Mac `docker` guard and prompt marker; loaded by one `source` line in
  `~/.zshrc`.
- Guide — the published runbook artifact and `README.md`, both using the icon legend.

### `sandbox` subcommands

- `new <firm> <git-url|zip>` — create volume `jt-<firm>` and fill it (README Phase 2 / Task 2).
- `scan <firm> <read command>` — throwaway container, `--network none`, volume `:ro`.
- `up <firm> [--accept-question]` — start the work container. **Refuses** unless
  `work/<firm>/scan.md` contains the verdict `Green`; `Question` needs `--accept-question`;
  `Red` or a missing file always refuses. Prints URL and generated password once.
- `exec <firm> <command>` — `docker exec` into the running work container as `dev`.
- `apply <firm>` — read a unified diff on stdin, run `git apply` inside the container, print
  `git diff --stat`. Lets Claude change test code without the code touching the Mac disk.
- `export <firm>` — `git bundle` + `git archive` into `work/<firm>/out/`.
- `rm <firm>` — asks for confirmation (typing the firm name), then removes container and
  volume.
- `status [firm] [--short]` — per `jt-*`: volume present, scan verdict, container state, and
  one line "next: …". `--short` prints one line for the statusline.

## Daily flow

Legend: 💬 tell Claude · 🖥 Mac terminal · 🧪 code-server · 🌐 browser (sandbox profile).

1. 🌐 Vet the sender (README Phase 2 / Task 1). No commands.
2. 💬 "new test acme <url>" or 🖥 `sandbox new acme <url|zip>`. A private repo's read token
   is typed by you in 🖥; Claude never sees it.
3. 💬 "scan acme" → Claude writes `work/acme/scan.md` with the verdict.
4. 💬 "status" or 🖥 `sandbox status` → next step.
5. 💬 "start acme" or 🖥 `sandbox up acme` → refuses without Green.
6. 🌐 Open `127.0.0.1:8443`; check the 🧪 orange bar and `🧪 SANDBOX acme` prompt.
7. 🧪 or 💬 `npm ci` — install scripts are off by default.
8. Work: 🧪 you edit; 💬 Claude reads via `scan`, runs via `exec`, changes via `apply`.
   App: 🧪 `npm run dev -- --host 0.0.0.0`, 🌐 `127.0.0.1:5173`.
9. 🧪 Commit in the code-server terminal.
10. 💬 "export acme" or 🖥 `sandbox export acme`.
11. 🖥 Send or push from the Mac yourself. Claude never pushes to an employer's repo.
12. 💬 "remove acme" or 🖥 `sandbox rm acme` → confirmation required.

## Working with Claude — accepted limits

- No Read/Edit/Write/Grep tools on test code; reading goes through `sandbox scan`, changes
  through patches and `sandbox apply`. Slower than normal editing, especially for many small
  changes.
- No live IDE diagnostics; Claude sees type and lint errors only by running them via `exec`.
- The hook allowlist means occasional permission prompts and rule updates for new command
  kinds.
- Claude cannot see the running app; share a screenshot when needed.
- In exchange: no token in the container worth stealing, and no Claude tool touches test files
  on the Mac.

## Guardrails

### Layer 1 — Claude hook (strict; only when Claude runs in this repo)

Allowlist; anything not listed is refused with a message naming the correct command.

- Allowed: `bin/sandbox <anything>`; reading and writing files inside this repo except
  `.claude/settings*.json` and `.claude/hooks/`; `git` except `push`.
- Refused explicitly (with a reason): direct `docker`; `npm`, `npx`, `node`, `pnpm`, `yarn`;
  `curl`, `wget`; `cd` or paths outside the repo; `git push`; any mention of `docker.sock`,
  `--privileged`, `-v /Users`.
- Exact `PreToolUse` hook input/exit-code contract and `permissions.deny` syntax are taken from
  the official Claude Code documentation at implementation time, not from memory.

### Layer 2 — Container defaults (only inside `job-sandbox:base` containers)

- `/etc/npmrc`: `ignore-scripts=true`. `npm rebuild <pkg>` remains the deliberate exception.
- `git config --system credential.helper ""`; the prompt shows a warning if a credential
  helper is set.
- Prompt: `🧪 SANDBOX <firm> ~/project $` on an orange background (`<firm>` from the container
  hostname `jt-<firm>`).
- code-server user settings: orange title and status bar
  (`workbench.colorCustomizations`), window title `🧪 SANDBOX — <firm>`.

### Layer 3 — Mac zsh guard (only for sandbox names)

- `docker` shell function inspects arguments only when they mention `jt-` or `job-sandbox`;
  otherwise it calls the real `docker` unchanged.
- For sandbox commands it refuses: `-v /…` and `--mount type=bind`, `docker.sock`,
  `--privileged`, `-p` without `127.0.0.1:`. The message names the matching `sandbox …`
  command.
- Inside `job-test-sandbox/`: warning (not a block) on `git clone` and `unzip`.
- Prompt marker `🛡 MAC · job-test-sandbox` only while the working directory is inside this
  repo.
- Escape hatch: `command docker …`.

### Statusline

`🛡 sandbox: <firm> · <verdict> · <running|stopped>` from `sandbox status --short`; shows
`🛡 sandbox: none` when no `jt-*` volume exists.

## Out of scope

- Claude CLI inside the container (rejected: needs a stealable API key).
- Running more than one work container at a time (ports stay fixed, as in README).
- Network egress filtering for the container (README residual risk, unchanged).

## Open risks

- code-server colour settings via a baked-in `settings.json` are expected to work but are
  untested.
- The zsh `docker` function may interfere with `docker` tab completion; checked in
  verification.
- Name-based filtering in Layer 3 misses sandbox commands that mention neither `jt-` nor
  `job-sandbox`; acceptable because Layer 3 only guards against mistakes.

## Verification

Run on this Mac after OrbStack is installed and the image is built. Every check must give the
expected result.

1. Claude hook — from Claude in this repo: `docker run -v /Users:/x job-sandbox:base true`,
   `npm i`, and `git push` are refused with a reason; `bin/sandbox status` runs.
2. Container — `sandbox exec acme npm config get ignore-scripts` prints `true`;
   `sandbox exec acme git config --system credential.helper` prints an empty value; the
   code-server terminal prompt starts with `🧪 SANDBOX acme`; title and status bar are orange.
3. Mac zsh — `docker run -v /Users:/x job-sandbox:base true` is refused;
   `docker run --rm hello-world` runs unchanged; `docker <TAB>` still completes; the prompt
   shows `🛡 MAC · job-test-sandbox` only inside the repo.
4. Gate — `sandbox up acme` refuses with no `scan.md`, with verdict `Red`, and with `Question`
   without `--accept-question`; starts with `Green`.
5. Apply — a one-line patch piped to `sandbox apply acme` shows up in
   `sandbox exec acme git diff`, and no file from the volume appears on the Mac disk.
6. Statusline shows the firm, verdict and container state.
7. All five checks in README Phase 7 pass.
