# Job test sandbox

Run take-home tests (small React apps and similar) from unknown companies without letting
their code touch the Mac.

> **Status:** `bin/sandbox`, the Claude guard hook, the statusline, the Mac zsh guard and
> `boilerplate/Dockerfile` are tested against a fake `docker` and checked on real Docker
> (OrbStack): the verification in FIRST-INSTALLATION.md (Task 7) and the checks in
> `docs/superpowers/plans/2026-10-01-sandbox-ux.md` (Phase 6) passed, except `npm rebuild`
> (needs a project with esbuild).

## Documents

- `FIRST-INSTALLATION.md` — one-time setup and its verification.
- `USER-GUIDE.md` — every command and step: who does what.
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
   USER-GUIDE.md, Phase 2).

## Guardrails

Three layers plus two always-on pieces, each scoped so normal work outside this repo and its
containers is untouched. Details: USER-GUIDE.md, Guardrails.

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
  `host.docker.internal`. Whether OrbStack exposes services bound only to `127.0.0.1` on
  the Mac this way is not stated in its docs and has not been tested here. While a test
  container runs, do not keep other local dev servers or admin panels open.
- **Container → internet and LAN.** The container needs the internet for npm, so malware
  could phone home, mine crypto or probe the home network (router, NAS). There is nothing
  to steal inside, the CPU and memory limits cap the damage, and you stop the container
  when idle.
- **Browser.** The test app's frontend runs in your browser. The separate profile
  (FIRST-INSTALLATION.md, Task 4) keeps it away from your real sessions.
- **VM or kernel escape.** Breaking out of the container and the OrbStack VM is possible
  in theory and rare in practice. Keep OrbStack updated.
- **Scan misses.** See USER-GUIDE.md, Phase 2 / Task 4; the container, not the scan, is the boundary.
