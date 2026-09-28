---
name: "source-command-qa-check"
description: "Migrated source command `qa-check`"
---

# source-command-qa-check

Use this skill when the user asks to run the migrated source command `qa-check`.

## Command Template

You are the ZehnStudio QA gate assistant. Before any task moves to the **`QA`** status in ZehnBoard (https://zehnboard.vercel.app), verify the evidence is complete. QA is one stage — Bee or Jawad reviews it.

## Purpose

**Operational efficiency.** Scripters used to write QA evidence by hand. It took time and was often incomplete, which made human QA painful — Jawad/Sadeeq (MG QA) and Bee (final QA) would discover problems that should have been caught earlier. This command moves the writing burden from human to AI: AI reads the code change, infers which tests are required, drafts the evidence, and asks the developer only to confirm results. The result: less manual typing for scripters, better evidence quality, and human QA actually catches what should be caught.

**Design principle:** Extract first, ask once. The developer should confirm AI's pre-filled draft, not type out fields by hand.

---

## Auto-extraction (run silently before asking anything)

1. Detect developer name from `git config user.name`. Compute `{name_slug}` (slug rule in start-day.md).
2. **Sync studio-ops-repo safely**:
   ```
   git -C ../../studio-ops-repo status --short
   git -C ../../studio-ops-repo pull --rebase origin main
   ```
   If pull fails, show error and continue with local copy.
3. Run `git branch --show-current` to capture branch.
3. Run `git diff main...HEAD --stat` to see what changed in this branch.
4. Look at file paths and diff content to infer:
   - **Affected systems** (combat, AI, UI, networking, data, etc.)
   - **Likely Issue Key** (from branch name or recent commit messages)
   - **Which test categories are needed** (use the rules below)

### Required test inference rules

Mark a test as "required" if:

| Test | Required when |
|---|---|
| **Play Solo** | Always (baseline) |
| **Output Error Check** | Always (baseline) |
| **Multiplayer Test** | Diff touches networking, RemoteEvents, server scripts, or shared state |
| **Mobile Test** | Diff touches UI, input handling, or anything user-facing |
| **Rejoin / Respawn Test** | Diff touches DataStore, player attributes, persistent state, or character spawning |
| **Performance Check** | Diff touches loops, physics, AI, particle effects, or large asset loads |

---

## Single user interaction (one batch confirmation)

Show the pre-filled QA evidence draft to the developer. Then ask:

> **Please mark each test as Pass / Fail / Skip and paste evidence links if you have them (otherwise write "later").**

Present the draft as a fillable form. Do **not** ask each field separately. The developer fills in test results in one pass.

---

## AI Judgment (auto)

After the developer answers, output one of these recommendations:

- **Move to "QA by MG"** — all required tests Pass, evidence linked, no critical bugs. Hand off to Jawad / Sadeeq for manager review.
- **Stay in "In Progress" — Needs Fix** — a required test Fail, or critical bug found. Fix before progressing.
- **Stay in `in_progress` — Blocked** — cannot test due to dependency or environment. Add a `Blocked` note in the QA file and as a comment on the issue in ZehnBoard.

---

## Output

Save QA evidence to `../../studio-ops-repo/members/{name_slug}/qa/{project}_{YYYY-MM-DD}_{issue_key}.md`:

```md
# QA Evidence — {issue_key}

| Field | Value |
|-------|-------|
| Issue Key | {issue_key} |
| Feature | {AI-extracted from diff} |
| Tester | {name_slug} |
| Date | {today} |
| Branch | {branch} |
| Commits in scope | {commit hashes} |
| What Changed | {AI-extracted from diff} |
| Affected Systems | {AI-inferred} |
| Test Environment | {Roblox Studio / Live / Mobile} |

## Required Tests (AI-determined) and Results

| Test | Required? | Result | Notes |
|------|-----------|--------|-------|
| Play Solo | Yes | Pass / Fail / Skip | |
| Output Error Check | Yes | | |
| Multiplayer Test | {Yes/No} | | |
| Mobile Test | {Yes/No} | | |
| Rejoin / Respawn Test | {Yes/No} | | |
| Performance Check | {Yes/No} | | |

## Evidence Links
{video / screenshot / Drive links}

## Bugs Found
{list, or "None"}

## Remaining Risk
{risk, or "None"}

## AI Recommendation (ZehnBoard status)
**{Move to "QA by MG" / Stay In Progress — Needs Fix / Stay In Progress — Blocked}**
Reason: {one-sentence justification}
```

After saving, **auto-push studio-ops-repo**:

```
git -C ../../studio-ops-repo add members/{name_slug}/qa/{filename}
git -C ../../studio-ops-repo commit -m "qa-check: {name_slug} {issue_key}"  || echo "Nothing to commit"
git -C ../../studio-ops-repo pull --rebase origin main
git -C ../../studio-ops-repo push origin main                               || echo "Push failed; QA evidence saved locally"
```

Then tell the developer (1 sentence): the recommendation and what to do next. If "Move to `qa`", point them to `/backlog-report` to draft the progress comment to paste into the issue in ZehnBoard.
