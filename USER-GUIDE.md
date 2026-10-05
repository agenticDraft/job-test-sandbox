# User guide

What you do every time you work on a test. One-time setup: FIRST-INSTALLATION.md. Every
subcommand, the guard rules and the raw `docker` commands: docs/reference.md.

Who does it: 💬 tell Claude · 🖥 you, Mac terminal · 🧪 you, code-server · 🌐 you, `sandbox` Chrome profile

Each step names where it runs: (Terminal) = Mac terminal, (Claude) = Claude Code in this repo,
(code-server) = the code-server terminal in the container, (Browser) = the `sandbox` Chrome profile.

## Your commands

**We use short aliases; they do not exist on a fresh machine.** `sandbox`, `guard-status`,
`guard-on`, `guard-off` and `claude` (the one that checks the guard) are our own zsh shell
functions, used like aliases, not standard tools. They are defined in `shell/sandbox.zsh`. Without
them (another machine, a plain bash shell) use the full command. Each entry below is: full
command first, then the short alias.

**To get the aliases** (zsh, one time; FIRST-INSTALLATION.md, Task 5): add this line to
`~/.zshrc`, after oh-my-zsh if you use it, and open a new terminal:

```bash
source <repo>/shell/sandbox.zsh
```

The file also adds the guard label to the prompt and the `docker`, `git clone`, `unzip` and `open`
checks inside this repo. If you only want the `sandbox` command and nothing else, a plain alias is
enough (any shell): `alias sandbox='<repo>/bin/sandbox'`. The `guard-*` aliases are only in
`shell/sandbox.zsh`; without it use the full commands.

First go into your clone of this repo (replace `<repo>` with its folder, for example
`~/github/agenticDraft/job-test-sandbox`). The full commands below run from there:

```bash
cd <repo>
```

```bash
# 🖥 Mac terminal, in the repo root. The full commands work in any shell; the short aliases need
# shell/sandbox.zsh and work from any directory. In Claude Code put ! in front, e.g. ! guard-status

# Guard state: must say GUARD IS ON before you work on a test
# full (the guard is on exactly when .claude/settings.json exists):
if [ -f .claude/settings.json ]; then echo "GUARD IS ON"; else echo "GUARD IS OFF"; fi
guard-status    # short alias

# Guard on: the normal state; needed only after guard-off
mv .claude/settings.json.off .claude/settings.json && echo "GUARD IS ON"   # full
guard-on                                                                   # short alias

# Guard off: ONLY to let Claude edit bin/, tests/ or .claude/ -- never with a test open
mv .claude/settings.json .claude/settings.json.off && echo "GUARD IS OFF"  # full
guard-off                                                                  # short alias

# Start Claude Code with the guard on (same word, different thing)
claude    # full: the plain Claude Code CLI; run "guard on" above first if the guard is off
          # short alias: our zsh function `claude` does that check itself, then starts the CLI

# Every project, its scan verdict and the next step
bin/sandbox status    # full
sandbox status        # short alias
```

Every `sandbox <subcommand>` in this guide is the short alias of `bin/sandbox <subcommand>`
(full command, from the repo root).

If Claude Code's `!` does not know `guard-on`, use the full command:

```bash
! mv .claude/settings.json.off .claude/settings.json   # guard on
! mv .claude/settings.json .claude/settings.json.off   # guard off
```

**Where am I?** `🛡 GUARD ON · MAC · job-test-sandbox` in the prompt → the Mac, guard on: never run
test code here. The shield shows only while the guard is on; a red `GUARD OFF · MAC · ...` without
the shield means it is off: run `guard-on` before you work on a test (the label updates on the
next prompt).
`🧪 SANDBOX firma` on orange → the container: test code runs only here.

## Docker in one minute

- **OrbStack** keeps a small Linux on the Mac; Docker runs in it. Its icon in the menu bar
  means it is running. You do nothing inside OrbStack; just keep it running.
- **Volume** `jt-firma` is a private disk in that Linux. The test's code lives there, never on
  the Mac disk.
- **Container** `jt-firma` is an isolated machine that sees only that volume; code-server and
  the test app run in it.
- **`sandbox`** creates and starts all of this. You never type `docker` yourself.

## A new test, step by step

Example: `firma.zip` arrived by email. The project name is yours: lowercase, digits, dashes.

**0. (Terminal) Before you start** — 🖥 OrbStack icon in the menu bar (if not: Cmd+Space, "OrbStack").

```bash
sandbox status   # "No projects..." or a list = Docker works; "cannot reach the Docker server" = start OrbStack
guard-status     # must say: GUARD IS ON
```

**1. (Browser) Vet the sender** — 🌐 unsolicited recruiter, crypto/web3, "just run our repo", urgency,
unknown domain, company you cannot verify: two or more → scan only, then decide.

**2. (Terminal) Put the code into the sandbox** — it is **copied** into the volume; nothing runs. Never
open, unzip or clone it on the Mac.

```bash
# 🖥 a zip: only you (the guard keeps Claude out of ~/Downloads)
sandbox new firma ~/Downloads/firma.zip
# 🖥 a git repo: private repos ask you for a read-only token
sandbox new firma https://github.com/firma/test.git
```

A public repo also works as 💬 "new test firma https://github.com/firma/test.git".

**3. (Claude) Scan** — start Claude here, never in a test folder:

```bash
cd ~/github/agenticDraft/job-test-sandbox && claude
```

💬 "scan firma" → Claude reads the code inside the sandbox (no network, read-only) and writes
`work/firma/scan.md`. **Green** → go on. **Question** → read scan.md, you decide. **Red** →
💬 "remove firma" and run nothing.

**4. (Terminal, then Browser) Start the work container** (after Green; or 💬 "start firma")

```bash
sandbox up firma   # refuses without Green; prints the password (also in work/firma/password)
```

🌐 Open `http://127.0.0.1:8443` in the `sandbox` profile and enter the password. Keep
Restricted Mode on until you have read the scan; close the Chat panel, do not sign in.

**5. (code-server) Work** — 🧪 code-server terminal (☰ → Terminal → New Terminal); prompt `🧪 SANDBOX firma`:

```bash
npm ci                          # install scripts are off by default
npm run dev -- --host 0.0.0.0   # then 🌐 http://127.0.0.1:5173
```

No `package.json` at the top → `cd` into the zip's folder first. 💬 Claude helps when asked:
"run the tests in firma", "fix the failing test in firma" (it applies a patch, you see the diff).

**6. (Terminal) End of the day**

```bash
sandbox stop firma   # next day: sandbox up firma -- your work stays in the volume
```

**7. (code-server, then Terminal) Hand in**

```bash
# 🧪 code-server terminal
git add -A && git commit -m "Solution"
# 🖥 Mac (or 💬 "export firma")
sandbox export firma   # writes work/firma/out/firma.zip and firma.bundle
```

🖥 Send `firma.zip` to the company yourself. Claude never sends or pushes anything.

**8. (Terminal) Clean up**

```bash
sandbox rm firma   # type "firma" to confirm (💬 "remove firma" works too; you confirm the prompt)
rm -r work/firma   # when you no longer need the scan and the export
```

## Who may do what

- **Only you:** tokens and passwords, a zip from `~/Downloads`, sending to the company,
  `guard-on` / `guard-off`, deleting `work/`.
- **Claude:** `scan`, `new` (public repo), `up`, `exec`, `apply`, `export`, `stop`, `rm`. It
  asks you first for `rm` and for starting a `Question` verdict. It never touches test files
  on the Mac, and it refuses to work on a test while the guard is off.
