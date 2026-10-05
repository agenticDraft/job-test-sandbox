# Job test sandbox

Run take-home tests (small React apps and similar) from unknown companies without letting
their code touch the Mac.

Public repo: https://github.com/agenticDraft/job-test-sandbox

## Terminal or Claude?

**You never type `docker`.** Every Docker call goes through one script, `bin/sandbox` (short
alias `sandbox`). You can run it from a plain Mac terminal, and Claude can run it from Claude
Code in this repo. It is the same script and the same Docker either way. What differs is who
you trust with the step.

- **Plain Mac terminal — you.** Everything that needs a secret or a file Claude must not see,
  plus the daily start and stop:
  - `sandbox new <firm> ~/Downloads/<firm>.zip` (a zip from Downloads; the guard keeps Claude out),
    or `sandbox new <firm> <url>` for a private repo (it asks you for a read-only token)
  - `sandbox up`, `sandbox stop`, `sandbox status`
  - sending `out/<firm>.zip` to the company, `guard-on` / `guard-off`, deleting `work/`
- **Claude Code in this repo — work on the test project.** Say what you want and Claude runs
  `sandbox` for you:
  - `scan <firm>` — reads the code with no network and the volume read-only, writes `work/<firm>/scan.md`
  - `run the tests in <firm>`, `fix the failing test in <firm>` — `exec` and `apply` (a patch; you see the diff)
  - also `new` (public repo only), `up`, `export`, `stop`; `rm` and starting a `Question` verdict ask you first
- **code-server terminal in the browser — you.** `npm ci`, `npm run dev`. This is the only
  place the test's code runs, inside the container.

Two things hold in all three. The test's code never runs on the Mac. And Claude starts in this
repo, never inside a test folder, with the guard on (`guard-status` must say `GUARD IS ON`). The
prompt tells you where you are: `🛡 GUARD ON · MAC · job-test-sandbox` is the Mac,
`🧪 SANDBOX <firm>` on orange is the container. Step by step: USER-GUIDE.md.

### How Claude works with the container

**Claude runs on the Mac, never in the container.** No Claude CLI and no token go into the
container. Claude cannot open the test's files, and has no editor or IDE inside it. It sees only
the text that `sandbox` prints, and it changes code only by handing `sandbox` a patch.

```
 Mac                                              OrbStack Linux VM
 ─────────────────────────────────                ───────────────────────────────────────
 Claude Code (started in this repo)
   │  every tool call
   ▼
 guard hook ── not on the allowlist ──▶ refused
   │  allowed
   ▼
 bin/sandbox <command>  ── docker ──▶  scan    throwaway container: no network, volume :ro
   ▲                                   exec    docker exec as `dev` in container jt-<firm>
   │  text output only                 apply   git apply <patch> in container jt-<firm>
   │                                   export  bundle + zip made from the volume
 work/<firm>/scan.md, out/  ◀── text and zips only
```

Example, "fix the failing test in acme":

1. `sandbox scan acme cat src/App.test.jsx` — Claude reads the file (throwaway container, no network). Text comes back.
2. Claude writes a patch file to its scratchpad on the Mac. It is text; nothing runs.
3. `sandbox apply acme <patch>` — `git apply` runs inside container `jt-acme`; Claude gets `git diff --stat`.
4. `sandbox exec acme npm test` — runs inside the container as user `dev`; Claude gets the printed result.
5. Repeat 1–4 until the test passes. You can open code-server in the browser to see the same code.

Each hop is checked. The guard hook allows only a fixed list of Claude tools and commands. `up`,
`exec` and `apply` reload the container firewall first. A step Claude is not allowed to take is
refused, not retried another way. Everything Claude reads from the test is data, not
instructions: text addressed to an AI is reported as a finding. Limits of this setup (slower for
many small edits, no live diagnostics, Claude cannot see the running app):
docs/reference.md, Working with Claude.

**Overview page:** https://claude.ai/artifact/P6jREw8p4i9BE8mQD3yLNa (architecture, rules,
guardrails and accepted risks on one page).

> **Status:** `bin/sandbox`, the Claude guard hook, the statusline, the Mac zsh guard and
> `boilerplate/Dockerfile` are tested against a fake `docker` and checked on real Docker
> (OrbStack): the verification in FIRST-INSTALLATION.md (Task 7) and the checks in
> `docs/superpowers/plans/2026-10-01-sandbox-ux.md` (Phase 6) passed, except `npm rebuild`
> (needs a project with esbuild).

## Documents

- `FIRST-INSTALLATION.md` — one-time setup and its verification.
- `USER-GUIDE.md` — what you do every time: your commands and a new test step by step.
- `docs/reference.md` — every `sandbox` subcommand, the guard rules in full, and each step with
  the raw `docker` command it runs.
- `CLAUDE.md` — rules for Claude in this repo.
- `docs/superpowers/` — design spec and plan.

## Why

Fake "coding test" repos are a known malware delivery channel aimed at developers (the
"Contagious Interview" campaign is the best-known example). The code runs at one of three
moments: `npm install` (`preinstall` / `install` / `postinstall` / `prepare` scripts, in the repo
or in any dependency), starting the app (obfuscated code in `vite.config.*`, `next.config.*`,
`tailwind.config.*` or a server file), or opening the folder in an editor (`.vscode/tasks.json`
with `"runOn": "folderOpen"`). Typical payloads steal browser passwords, crypto wallets, SSH keys
and tokens. The defence: **that code never runs on the Mac, and nothing worth stealing is inside
the box it runs in.**

## Architecture

```
 Mac (host)                                  OrbStack Linux VM
 ─────────────                               ─────────────────────────────────────────
 job-test-sandbox/ (this repo)               image  job-sandbox:base   (never modified)
   boilerplate/Dockerfile ── build once ──▶        │
   bin/sandbox                                     ├─▶ volume   jt-<firm>   (the test's code)
   work/<firm>/scan.md ◀── text only ──┐           │
   work/<firm>/out/    ◀── export ─────┤           ├─▶ container jt-<firm>  (work: code-server)
                                       │           │
 Claude Code (in job-test-sandbox)     │           └─▶ throwaway container  (scan: --network none,
   reads only through sandbox scan ─┘                                         volume mounted :ro)
 Browser ── 127.0.0.1:8443 (code-server), 127.0.0.1:5173 (the app) ──▶ container jt-<firm>
```

- **`job-sandbox:base` image** — Node 24, git, unzip, curl, code-server; runs as user `dev`, not
  root. Built once, rebuilt only on purpose (Node or code-server update).
- **`jt-<firm>` volume** — the test's code lives here and **never on the Mac disk**.
- **`jt-<firm>` container** — one per project, from the image: code-server and the app. No bind
  mounts, no Docker socket, all capabilities dropped, ports bound to `127.0.0.1` only.
- **throwaway scan container** — the only way Claude looks at the code: no network, volume
  read-only, removed after each command.
- **`work/<firm>/`** on the Mac holds only text Claude wrote (`scan.md`) and what you exported
  (`out/`). It is gitignored: it shows where you applied.

"A new clone for each project" means a new volume plus a new container from the same image.
The image itself is never copied or changed.

## Rules (non-negotiable)

1. **Never clone, unzip or open a test repo on the Mac.** Not in Finder, not in VS Code,
   not in a terminal. It goes straight into a volume.
2. **No bind mounts** (`-v /Users/...:/...`) and **never** mount `/var/run/docker.sock`.
3. **No credentials in the container.** No `~/.ssh`, no main GitHub token, no `.npmrc`
   with a token. A token for delivery is fine-grained, limited to one repo, typed at push
   time and never saved.
4. **Ports bind to `127.0.0.1`**, never `0.0.0.0` on the Mac side.
5. **Nothing runs before the scan is green**, including `npm install`.
6. **Use Docker containers only, not OrbStack "machines".** Machines see Mac files at
   `/mnt/mac` by default; containers do not.
7. **Claude never starts inside a test repo** and never runs anything from it (see
   docs/reference.md, Phase 2).

## Guardrails

Three layers plus two always-on pieces, each scoped so normal work outside this repo and its
containers is untouched. Details: docs/reference.md, Guardrails.

- **Claude guard** (`.claude/hooks/guard.sh`, the real boundary): strict allowlist for Claude's
  tools, applied only when Claude Code runs in this repo. On while `.claude/settings.json`
  exists. You switch it with the zsh functions `guard-on`, `guard-off` and `guard-status`
  (Claude cannot); the `claude` wrapper switches it on before Claude Code starts in this repo.
  While it is off, `bin/sandbox` refuses test-code commands from Claude.
- **Container defaults** (inside `job-sandbox:base` containers): npm install scripts off,
  no git credential helper, orange prompt and code-server bars, no automatic tasks.
- **Mac zsh guard** (`shell/sandbox.zsh`; guards against mistakes, not attacks): refuses
  `docker run|create` with bind mounts, `docker.sock`, `--privileged` or ports not on
  `127.0.0.1`, and blocks `git clone`, `unzip` and opening archives inside this repo.
- **Intake hook for Claude** (`.claude/hooks/no-intake.sh`): always on, even with the guard off;
  no clone, no unpacking, no opening archives.
- **Statusline**: `🛡 sandbox: <firm> · <verdict> · <running|stopped>`.

## Residual risks (accepted)

- **Container → Mac services.** Containers can reach servers on the Mac through
  `host.docker.internal`, including servers bound only to `127.0.0.1` (tested on OrbStack,
  2026-10-03). OrbStack has no setting that blocks this for Docker containers, so every
  `sandbox up` firewalls the work container: the Mac (`0.250.250.254`), the rest of OrbStack's
  `0.0.0.0/8` except DNS, `198.18.0.0/15` and private ranges are rejected from inside its own
  network namespace (`bin/container-firewall.sh`), and nothing on the Mac is touched. A restart
  drops the rules, and `sandbox up` loads them right after it starts the container, so for that
  moment only code-server runs unfirewalled (a restart ends anything you started in it, and
  automatic tasks are off). `sandbox exec` and `sandbox apply` reload the rules first, so a
  container started outside `sandbox up` (the OrbStack app, `docker start`) is firewalled before
  anything runs in it. Code-server and the app inside it run unfirewalled until then; start the
  container only with `sandbox up`.
- **Container → internet.** The container needs the internet for npm, so malware could
  phone home or mine crypto. The home network (router, NAS) is blocked by the same firewall
  (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`, link-local, multicast); a VPN whose
  addresses are outside those ranges is not. IPv6 is off in the container on OrbStack's
  default network (checked 2026-10-05: only `lo` in `/proc/net/if_inet6`); if it is ever on,
  IPv6 from the container is blocked except ICMPv6. There is nothing to steal inside, the CPU and
  memory limits cap the damage, and you stop the container when idle.
- **Delivery token.** Code that ran in the container can write the repo's own `.git/config`
  (`credential.helper`, `core.askPass`, `url.<base>.insteadOf`) and `.git/hooks`, so a token typed
  at `git push` inside the container can leak, and the internet is open. Deliver with
  `sandbox export` (no network, volume read-only) and push the bundle from the Mac. If you must
  push from the container, read `git config --local --list` and `.git/hooks` first.
- **Browser.** The test app's frontend runs in your browser, on the Mac, so the container
  firewall does not apply to it. The separate profile (FIRST-INSTALLATION.md, Task 4) keeps it
  away from your real sessions, but not from the network: its JavaScript can send requests to
  servers on the Mac's `127.0.0.1` and the home network. The browser keeps it from reading the
  replies unless the server allows it (CORS), but a request that changes something still lands.
  **While the test app is open, do not keep other local dev servers or admin panels running.**
- **VM or kernel escape.** Breaking out of the container and the OrbStack VM is possible
  in theory and rare in practice. Keep OrbStack updated.
- **Scan misses.** See docs/reference.md, Phase 2 / Task 4; the container, not the scan, is the boundary.
