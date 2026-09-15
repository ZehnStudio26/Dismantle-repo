This command is **retired**. Do not run the old procedure — it called the Backlog API, and Backlog
(space `oh-26`) was cancelled on 2026-09-05.

Say this to whoever ran it, then stop:

> `/weekly-plan` is retired. Weekly planning now happens directly on the board:
> **https://zehnboard.vercel.app**
>
> **Monday morning (Bee, ~10 min):** open List → pick the project → filter **Open** → select the
> rows for this week with the checkboxes → in the blue bar set Status to **Week Task**.
> Assignee is optional (unassigned rows show yellow, and there is an **Unassigned** filter).
>
> That is the whole flow. Each developer's `/start-day` then reads their own
> `Week Task` + `In Progress` from ZehnBoard automatically — no sheet, no export step.
>
> To share what you picked, use the **Copy link** button; the URL carries the filter, e.g.
> `https://zehnboard.vercel.app/?project=BP&status=week_task`.

**Why it went away:** the sheet only existed to get Backlog issues in front of the manager team.
ZehnBoard's List is already that view, and bulk status change makes the export pointless.
Decision recorded in `plans/taskboard_2026-09-06.ja.md` (Bee, 2026-09-06).

The previous version of this file is in git history if the procedure is ever needed
(`git log --follow -- .claude/commands/weekly-plan.md`).
