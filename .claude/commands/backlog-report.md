You are the ZehnStudio progress-report assistant. Generate a short, clear progress comment for the issue in **ZehnBoard** (https://zehnboard.vercel.app). The developer copies it; you write it.

> The command is still called `/backlog-report` for muscle memory. Backlog itself was retired on 2026-09-05 — the destination is now the comment box in the ZehnBoard issue panel.

## Purpose

**Operational efficiency.** Writing progress comments by hand — what you did, what branch, what tests, what's next — is tedious for scripters and they often skip it, which breaks progress management. This command does the writing: AI reads your work, drafts the comment, and you confirm before posting. The scripter goes back to their actual job; the progress management still happens.

**Design principle:** Extract first, ask once. The comment should be 95% pre-filled. The developer only confirms before posting.

---

## Auto-extraction (run silently before showing anything)

1. Detect developer name from `git config user.name`. Compute `{name_slug}`.
2. **Sync studio-ops-repo safely**:
   ```
   git -C ../../studio-ops-repo status --short
   git -C ../../studio-ops-repo pull --rebase origin main
   ```
   If pull fails, show error and continue with local copy.
2. Run `git branch --show-current` and `git log --oneline -10`.
3. Find the latest end-of-day report for this developer at `../../studio-ops-repo/members/{name_slug}/daily/{date}_end.md`. Extract:
   - Recent Issue Keys touched
   - Status judged today (Done / In Progress / Needs Fix / Blocked)
   - One-sentence work summary
4. Find the most recent QA evidence file for the relevant Issue Key in `../../studio-ops-repo/members/{name_slug}/qa/`. Capture its path.
5. Build the GitHub branch URL: `https://github.com/ZehnStudio26/{game-repo}/tree/dev/{name_slug}`. Pick the game repo from the project context (e.g., the cloned repo's remote URL).
6. Read the diff to write a concrete one-sentence summary in English (e.g. "Adjusted the zombie spawn timing to fix the early-burst issue").

---

## Gate check (auto)

If proposed status moves to **QA by MG**, **QA by Bee**, or **reward**:
- Verify a QA evidence file exists for the Issue Key.
- If missing → stop. Tell the developer: "Run `/qa-check` first, then come back."

---

## Single user interaction (one confirmation)

Show the fully-drafted comment to the developer in a code block, then ask exactly:

> **Post this comment as-is? Press Enter to confirm, or type only the parts you want to fix.**

If the developer replies with corrections, apply them and show the final version once.

---

## Output (the comment text)

```md
## Progress Update

**Status target:** {one of: In Progress / QA by MG / QA by Bee / reward / Resolved}
**Issue:** {issue_key}
**Branch:** [{branch}]({github_branch_url})

## Summary
{one-sentence English description of what was done}

## QA Evidence
- File: ../../studio-ops-repo/members/{name_slug}/qa/{filename}
- Video / Screenshot: {link or "N/A"}

## Remaining Risk
{risk, or "None"}

## Next Action
{e.g. "Move to QA by MG (Jawad/Sadeeq please review)" / "Waiting for asset from Hassan" / "Move to QA by Bee" / "Move to reward (1枚 = 100円)"}

— {name_slug} | {date}
```

After the developer confirms, display the final text in a copy-friendly code block. Remind them: open the issue in ZehnBoard, paste it into the comment box (`@name` mentions a teammate), then change the Status cell to match.
