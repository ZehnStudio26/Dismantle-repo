You are the ZehnStudio session-save assistant. Run this **before switching to another project** or **before logging off mid-day**.

## Purpose

**Resource extraction & forced backup at session boundaries.**

Real situation: a developer might work on Last Town in the morning, switch to Core Defence at lunch, and Bloom Prison in the afternoon. By `/end-day`, AI sees only the current project's git state and would lose the morning's session. This command captures **each session as it ends**, so `/end-day` can aggregate the full day correctly.

It also acts as a forced-backup checkpoint — your work goes to GitHub before you context-switch.

**Required**: run this before switching projects. Recommended: also run before lunch / leaving desk.

**Design principle:** Extract first, ask once.

---

## Personal account guard (check FIRST, before anything else)

Run `git config user.name` and `git config user.email`. If **either** value contains a shared studio account — `zehn03`, `zehn05`, or the retired `ismailazam2233` — **STOP immediately**. Do not commit or push your game-repo or write the session log (a git hook will reject the commit anyway). Tell the developer, showing the value found:

> ⚠️ Your machine is committing as a **shared account** (`{value}`) — your work can't be credited to you. Set your own identity once, then run `/save-work` again:
> ```
> git config --global user.name  "Your Name"
> git config --global user.email "your-github-email"
> ```
> Stuck? Ask Jawad — see `guides/vscode-claude-setup.md`.

---

## Auto-extraction (run silently)

1. Detect name from `git config user.name`. Compute `{name_slug}` (see start-day.md slug rule).
2. Identify current project (current game-repo from cwd, e.g. `lasttown-repo` → "Last Town Survival"). For games that are on ZehnBoard, note the project key (`VM` / `BP` / `MS`).
3. Run `git status`, `git diff origin/dev/{name_slug}...HEAD`, `git log --oneline @{u}..` (commits since last push).
4. Read diff content and recent commit messages.
5. Detect the issue key from branch name, recent commits, or related daily report (`VM-12`; retired Backlog keys like `THEVERMILIONMASK-123` may appear in older commits).
6. AI extracts:
   - **What was accomplished this session** (1-3 sentences from the diff)
   - **Skills demonstrated** (debugging, refactoring, performance, AI-assist, asset integration, etc.)
   - **Trial-and-error / failed approaches / lessons** (from commits, dialog history if accessible)
   - **Time on this session** (rough estimate from commit timestamps)
   - **Next pickup point** (where to resume)
7. **Sync studio-ops-repo safely**:
   ```
   git -C ../../studio-ops-repo status --short
   git -C ../../studio-ops-repo pull --rebase origin main
   ```
   If pull fails, show error and continue with local copy.

---

## Single user question

> **Any blocker or learning? (Enter to skip)**

That's it. Optional input.

---

## Auto-push (both repos)

After extraction, push:

1. **Game-repo** — stage, commit, push to `dev/{name_slug}`:
   ```
   git add .
   git commit -m "{IssueKey}: {AI-generated one-line summary}"  || echo "Nothing to commit"
   git push origin dev/{name_slug}                              || echo "Push failed; will retry next time"
   ```
2. **studio-ops-repo** — write session log, then commit + push (with re-pull):
   ```
   # write the session log file...
   git -C ../../studio-ops-repo add members/{name_slug}/work_history/...
   git -C ../../studio-ops-repo commit -m "save-work: {name_slug} {project} {date} {time}"  || echo "Nothing to commit"
   git -C ../../studio-ops-repo pull --rebase origin main
   git -C ../../studio-ops-repo push origin main                   || echo "Push failed; saved locally"
   ```

If a commit returns "nothing to commit" or push fails, show the exact message and continue. Do not abort.

---

## Session log (the file written)

`../../studio-ops-repo/members/{name_slug}/work_history/{YYYY-MM-DD}_{HHMM}_{project}.md`:

```md
# Session — {name_slug} — {YYYY-MM-DD} {HH:MM} — {project}

## Project
{Game name} (repo: {game-repo-name}, branch: dev/{name_slug})

## Issue Key
{KEY-N, or "—" if not detected}

## What I Did This Session
{1-3 sentence summary derived from git diff}

## Skills Demonstrated
- {e.g. "Debugging multiplayer state desync"}
- {e.g. "Refactoring spawn config out of runtime logic"}

## Trial-and-Error / Lessons
{Failed approaches or insights — knowledge gold for /weekly-review pattern extraction}
- {e.g. "Tried X first, didn't work because Y. Solved with Z."}

## Blockers / Learnings (from developer)
{Their answer, or "None"}

## Time
~{hours}h (from {start commit time} to {end commit time})

## Next Pickup
{What to resume next time on this project}

## Commits in this session
- {hash} {message}
- ...
```

After pushing, tell the developer (1 sentence): "Session saved to {project}/dev/{name_slug} and work history. You can switch projects or log off."
