# First installation

Do these tasks once per Mac, in order: install OrbStack, lock its settings, `sandbox build`, Chrome
profile, `~/.zshrc` line, intake hook, then the verification. After that use USER-GUIDE.md.

## Task 1 — Install OrbStack

**Who:** 🖥 you, in a normal terminal (it may ask for your Mac password). Claude does nothing here.

Download from orbstack.dev. The free tier is "personal, non-commercial use". Doing a test
for your own job application reads as personal use, but their page does not define this
precisely.

1. Check the chip: `uname -m` prints `arm64` (Apple Silicon) or `x86_64` (Intel). The
   Homebrew cask picks the right build; on the website, choose the matching download.
2. Install, in a normal terminal (it may ask for your Mac password):

   ```bash
   brew install --cask orbstack
   ```

   It may first print "Auto-updating Homebrew..." and pause; that is normal. It ends with
   `orbstack was successfully installed!`.
3. Start it once: Cmd+Space, type "OrbStack", Enter (or `open -a OrbStack`). On "What do
   you want to use?" choose **Docker**, not Linux (a Linux machine sees Mac files, README Rule 6)
   and not Kubernetes. While its menu bar icon is there, Docker is running; there is no
   separate Docker app to start.
4. Check, in a new terminal:

   ```bash
   command -v docker                                      # prints a path
   docker version --format 'server {{.Server.Version}}'  # server version, not "Cannot connect"
   ```

Updates later: `brew upgrade --cask orbstack`.

## Task 2 — Lock down OrbStack settings

**Who:** 🖥 you, in the OrbStack app (menu bar icon → Settings).

- Docker settings → turn **off** "Expose ports to LAN" (`docker.expose_ports_to_lan`).
  By default, published ports are reachable from other devices on your network.
- Do not create any OrbStack Linux machines for this.

## Task 3 — Build the base image

**Who:** 🖥 you: `sandbox build`, or 💬 "build the sandbox image" (Claude runs
`bin/sandbox build`). Takes a few minutes the first time. Rebuild only on purpose (Node or
code-server update, or a change in `boilerplate/`).

```bash
sandbox build
# what it runs for you (do not type):
docker build -t job-sandbox:base boilerplate
```

## Task 4 — Use a separate browser profile

**Who:** 🌐 you, in Chrome. Claude does nothing here.

1. In the address bar open `chrome://profile-picker` → **Add**.
2. Choose **Stay signed out** (older versions: "Continue without an account"). Do not sign in.
3. Name it `sandbox` and pick a loud colour (orange).
4. In that window: Settings → **Autofill and passwords** → turn off saving passwords,
   addresses and payment methods. Install no extensions and log in to nothing there.

You open code-server and the test app only in this profile. The test app's frontend code
runs in the browser, so it must not share a profile with your email or GitHub session.
Incognito is weaker: it can still fill passwords saved in your main profile and runs
extensions you allowed in incognito.

## Task 5 — Load the Mac shell guard

**Who:** 🖥 you (`open -t ~/.zshrc`). Claude may not edit files outside this repo. Then open a
new terminal and check: `cd ~/github/agenticDraft/job-test-sandbox` shows
`🛡 MAC · job-test-sandbox`, and `sandbox status` answers.

Add one line to `~/.zshrc`, **after** oh-my-zsh is loaded:

```bash
source ~/github/agenticDraft/job-test-sandbox/shell/sandbox.zsh
```

It defines a `sandbox` function (so the command works from any directory), `guard-on` /
`guard-off` / `guard-status` for the Claude guard (docs/reference.md, Guardrails, "Scope, on and off"), a `claude`
wrapper that switches the guard on before Claude Code starts in this repo, and a `docker`
wrapper that only looks at `docker run|create` calls naming `jt-` or `job-sandbox`; every
other `docker` call passes through unchanged. Inside this repo it blocks `git clone`, `unzip`
and `open` of an archive (override: `command git clone …`), and puts the prompt marker
`🛡 MAC · job-test-sandbox` on the prompt while you are in this repo. See docs/reference.md, Guardrails / Layer 3.

## Task 6 — Keep Claude from cloning or unpacking, always

**Who:** 🖥 you create `.claude/settings.local.json` (the guard does not let Claude write
under `.claude/` except `artifacts/`). Then in Claude Code type `/hooks` once (or restart it),
and check with 💬 "run unzip -l x.zip": it must be refused.

The main guard (`.claude/settings.json`) can be switched off for maintenance. A second,
always-on hook covers intake: Claude may never run `git clone`, `gh repo clone`, `unzip`,
`ditto`, `tar`, `7z` and similar, or `open` an archive in this repo, guard on or off. It lives
in `.claude/hooks/no-intake.sh` (in git) and is registered in `.claude/settings.local.json`,
which is local-only (your global git ignore excludes it), so create it once per clone:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/bin/bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/no-intake.sh\"" }
        ]
      }
    ]
  }
}
```

Claude Code may ask you to review a new or changed hook (`/hooks`) or need a restart before
it takes effect. Check: ask Claude to run `unzip -l x.zip`; it must be refused with
"Blocked by the job-test-sandbox intake rule". A single `bin/sandbox new <firm> <zip>` call
is allowed: it streams the zip into the volume without unpacking it on the Mac. Finder
(double-clicking a zip) cannot be blocked by any script; README Rule 1 covers it.

## Task 7 — Verify

**Who:** 🖥 you (these call `docker` directly, which the guard does not let Claude do). A
project `acme` must exist and be running for checks 3–6: 🖥 `sandbox new acme
https://github.com/agenticDraft/job-test-sandbox.git`, write `Verdict: Green` into
`work/acme/scan.md`, `sandbox up acme`, run the checks, then `sandbox rm acme`.

Run once after Tasks 1-6, and again whenever the image or scripts change. Every line must
print the expected result. Then run the checks in Phase 6 of
`docs/superpowers/plans/2026-10-01-sandbox-ux.md` (guard hook, container defaults, zsh guard,
scan gate, apply, statusline); they cover everything the six checks below do not.

Check 6 needs two test servers on the Mac, each in its own terminal tab, stopped with Ctrl-C
afterwards: `python3 -m http.server 18765 --bind 127.0.0.1 --directory "$(mktemp -d)"` and
`python3 -m http.server 18766 --bind 0.0.0.0 --directory "$(mktemp -d)"`.

```bash
# 1. Image runs as non-root
docker run --rm job-sandbox:base id -u                  # expect: not 0

# 2. Mac files are not visible inside a container
docker run --rm job-sandbox:base ls /Users /mnt/mac     # expect: No such file or directory

# 3. Scan container has no network and cannot write
docker run --rm --network none --read-only -v jt-acme:/src:ro job-sandbox:base \
  sh -c 'touch /src/x; getent hosts registry.npmjs.org; echo done'
                                                        # expect: Read-only file system, no address

# 4. Work container: only the project volume is mounted, ports bound to localhost
docker inspect jt-acme --format '{{json .Mounts}}'      # expect: one volume, jt-acme
docker port jt-acme                                     # expect: 127.0.0.1:8443, 127.0.0.1:5173 only

# 5. All capabilities dropped
docker exec jt-acme grep CapEff /proc/self/status       # expect: 0000000000000000

# 6. Work container cannot reach the Mac or the LAN; npm and code-server still work
LAN="$(ipconfig getifaddr en0)"
for u in host.docker.internal:18765 host.docker.internal:18766 "$LAN:18766"; do
  docker exec jt-acme curl -sS -m 4 -o /dev/null -w "$u %{http_code}\n" "http://$u/"
done                                                    # expect: each 000, none 200
docker exec jt-acme curl -sS -o /dev/null -w "%{http_code}\n" https://registry.npmjs.org/
                                                        # expect: 200
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8443/
                                                        # expect: 302 or 200
```
