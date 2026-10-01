# User guide

What you do every time you work on a test. One-time setup: FIRST-INSTALLATION.md. Every
subcommand, the guard rules and the raw `docker` commands: docs/reference.md.

Who does it: 💬 tell Claude · 🖥 you, Mac terminal · 🧪 you, code-server · 🌐 you, `sandbox` Chrome profile

## Your commands

```bash
# 🖥 Mac terminal, any directory (functions from shell/sandbox.zsh).
# In Claude Code put ! in front, e.g. ! guard-status
guard-status     # must say "guard is on" before you work on a test
guard-on         # the normal state; needed only after guard-off
guard-off        # ONLY to let Claude edit bin/, tests/ or .claude/ -- never with a test open
claude           # in this repo: switches the guard on, then starts Claude Code
sandbox status   # every project, its scan verdict and the next step
```

If Claude Code's `!` does not know `guard-on`:

```bash
! mv .claude/settings.json.off .claude/settings.json   # guard on
! mv .claude/settings.json .claude/settings.json.off   # guard off
```

**Where am I?** `🛡 MAC · job-test-sandbox` in the prompt → the Mac: never run test code here.
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

**0. Before you start** — 🖥 OrbStack icon in the menu bar (if not: Cmd+Space, "OrbStack").

```bash
sandbox status   # "No projects..." or a list = Docker works; "cannot reach the Docker server" = start OrbStack
guard-status     # must say: guard is on
```

**1. Vet the sender** — 🌐 unsolicited recruiter, crypto/web3, "just run our repo", urgency,
unknown domain, company you cannot verify: two or more → scan only, then decide.

**2. Put the code into the sandbox** — it is **copied** into the volume; nothing runs. Never
open, unzip or clone it on the Mac.

```bash
# 🖥 a zip: only you (the guard keeps Claude out of ~/Downloads)
sandbox new firma ~/Downloads/firma.zip
# 🖥 a git repo: private repos ask you for a read-only token
sandbox new firma https://github.com/firma/test.git
```

A public repo also works as 💬 "new test firma https://github.com/firma/test.git".

**3. Scan** — start Claude here, never in a test folder:

```bash
cd ~/github/agenticDraft/job-test-sandbox && claude
```

💬 "scan firma" → Claude reads the code inside the sandbox (no network, read-only) and writes
`work/firma/scan.md`. **Green** → go on. **Question** → read scan.md, you decide. **Red** →
💬 "remove firma" and run nothing.

**4. Start the work container** (after Green; or 💬 "start firma")

```bash
sandbox up firma   # refuses without Green; prints the password (also in work/firma/password)
```

🌐 Open `http://127.0.0.1:8443` in the `sandbox` profile and enter the password. Keep
Restricted Mode on until you have read the scan; close the Chat panel, do not sign in.

**5. Work** — 🧪 code-server terminal (☰ → Terminal → New Terminal); prompt `🧪 SANDBOX firma`:

```bash
npm ci                          # install scripts are off by default
npm run dev -- --host 0.0.0.0   # then 🌐 http://127.0.0.1:5173
```

No `package.json` at the top → `cd` into the zip's folder first. 💬 Claude helps when asked:
"run the tests in firma", "fix the failing test in firma" (it applies a patch, you see the diff).

**6. End of the day**

```bash
sandbox stop firma   # next day: sandbox up firma -- your work stays in the volume
```

**7. Hand in**

```bash
# 🧪 code-server terminal
git add -A && git commit -m "Solution"
# 🖥 Mac (or 💬 "export firma")
sandbox export firma   # writes work/firma/out/firma.zip and firma.bundle
```

🖥 Send `firma.zip` to the company yourself. Claude never sends or pushes anything.

**8. Clean up**

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
