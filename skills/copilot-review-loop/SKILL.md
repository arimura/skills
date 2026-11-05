---
name: copilot-review-loop
description: Use when asked to open a pull request and iterate on GitHub Copilot code review until its feedback converges, or to run repeated Copilot review rounds on an existing PR (e.g. "PR作ってCopilotレビューを収束するまで回して", "loop Copilot review", "address Copilot comments until it's clean").
---

# Copilot Review Loop

## Overview

Open (or reuse) a PR, then repeat **request Copilot review → wait for the review of the current head → triage every comment → push fixes / reply / resolve** until Copilot has nothing new worth acting on, or the round cap is hit.

Core principle: **a round is anchored to a head commit.** The review you wait for is the Copilot review whose `commit_id` equals the PR head at request time. Never push while that review is pending, and never treat an older review as the answer.

Defaults (the user may override any of them):

| Setting | Default |
|---|---|
| Max rounds | 5. A round is one head commit reviewed by Copilot; the first review is round 1. A re-request after a timeout or error belongs to the same round. |
| Wait per review | 15 min, poll every 30 s |
| PR state | Ready for review (not draft): automatic Copilot review can skip drafts |

## Pick the tooling

- `gh auth status` succeeds → use **gh** (commands below).
  - The helper scripts live in this skill's own directory, not in the repository under review. Call them by absolute path: `bash <skill-dir>/scripts/...`, where `<skill-dir>` is the directory that contains this SKILL.md.
  - Keep the working directory in the target repository, because `gh` reads the repository from the working directory.
- Otherwise, if `mcp__github__*` tools are available → use **MCP** (right-hand column of the table).
- Neither → stop and tell the user.

Copilot's reviewer login differs by API: REST reviews `copilot-pull-request-reviewer[bot]`, GraphQL and the MCP thread list `copilot-pull-request-reviewer`, webhook payloads `Copilot`. Match those exactly. Do not match `/copilot/i`: it also catches `copilot-swe-agent` (the coding agent). If threads come from the coding agent, leave them alone and mention them in the report.

Code always reaches the branch through `git commit` + `git push`, in MCP mode too. If `git push` has no credentials, stop and tell the user. Do not use `push_files` or `create_or_update_file`: they create remote commits that the local branch does not have.

| Step | gh | GitHub MCP |
|---|---|---|
| Find existing PR | `gh pr list --head <branch> --state open --json number,url` | `list_pull_requests` (head=`owner:branch`) |
| Create PR | `gh pr create --base <base> --title ... --body-file ...` | `create_pull_request` |
| Head SHA | `gh pr view <n> --json headRefOid -q .headRefOid` | `pull_request_read` method `get` → `head.sha` |
| Already requested? | `gh pr view <n> --json reviewRequests` | not exposed; request unconditionally |
| Review baseline (before requesting) | `bash <skill-dir>/scripts/wait-for-copilot-review.sh baseline <n>` | `pull_request_read` method `get_reviews` → largest `id` among Copilot reviews (0 if none) |
| Request review | `gh pr edit <n> --add-reviewer @copilot`; if unsupported: `gh api -X POST repos/{o}/{r}/pulls/<n>/requested_reviewers -f 'reviewers[]=copilot-pull-request-reviewer[bot]'` | `request_copilot_review` |
| Wait for review | `bash <skill-dir>/scripts/wait-for-copilot-review.sh wait <n> <baseline> <head-sha>` | poll `pull_request_read` method `get_reviews` for a Copilot review with `id` > baseline and `commit_id` == head SHA |
| Unresolved Copilot threads | `bash <skill-dir>/scripts/copilot-threads.sh <n>` | `pull_request_read` method `get_review_comments`; keep threads with `is_resolved: false` whose first comment's author is Copilot's |
| Reply to a thread | `gh api -X POST repos/{o}/{r}/pulls/<n>/comments/<comment_id>/replies -f body='...'` | `add_reply_to_pull_request_comment`. The numeric `commentId` is the number in the comment's `html_url` anchor `#discussion_r<id>` |
| Resolve a thread | `gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -F id=<thread_id>` | `resolve_review_thread` (`PRRT_...` id) |

In MCP mode, `get_reviews` and `get_review_comments` are paginated, and your own thread replies show up as reviews too. Read every page (`perPage` 100, then the next page or the `after` cursor) before taking a baseline or deciding that no new review has arrived. The newest review is on the last page.

`wait-for-copilot-review.sh wait` has three outcomes:
- exit 0: the review was found, and its JSON is printed.
- exit 2: timeout.
- exit 3: the PR head moved during the wait. Its default 15‑minute wait is longer than a default shell-tool timeout, so run it with a longer timeout or in the background.

In MCP mode, wait for the review in one of two ways:
- If the harness can subscribe to PR activity, subscribe. The review's arrival then wakes the session.
- Otherwise, poll at least 30 s apart, using whatever wait mechanism the harness provides.

## The loop

**0. Pre-flight.** The working tree is clean, and the branch is pushed and matches the remote. Run the repo's own fast checks (tests and lint) so Copilot does not review broken code. Reuse an open PR for the branch if one exists. Otherwise create one, following the repo's PR template if it has one.

**1. Request.** Record the head SHA, and the review baseline: the id of the newest existing Copilot review. If Copilot is already a requested reviewer (because a ruleset auto-requested it on PR creation or on push), skip the request. Otherwise request it. If the request fails with 404 or 422, or Copilot never appears as a reviewer, Copilot review is not enabled here. Stop and report that.

**2. Wait** for a Copilot review that is newer than the baseline and on that head SHA. Do not push during the wait. Anything you change meanwhile stays local and goes into this round's commit in step 5.
- If the wait times out, take a fresh baseline, re-request once and wait again. If the second wait also times out, stop and report.
- If the review body says Copilot hit an error or could not review, take a fresh baseline and re-request once.
- If the PR head moves during the wait, someone else pushed. Pull their commits, then restart this round on the new head with a fresh baseline.

**3. Collect.** List the unresolved Copilot threads, and read the review body too. The body can carry findings that have no inline thread, such as "low confidence" comments or "previously missed issues" in unchanged code. Triage those as well. They have no thread to reply on, so post their verdicts as one PR comment.

**4. Triage each comment** against the actual code. Keep a ledger of every verdict across rounds (round, comment, verdict, sha or reason). You need it to spot repeats and to write the report. Every comment gets exactly one verdict:

| Verdict | When | Action |
|---|---|---|
| **Fix** | Real bug, correctness, security, edge case, or a cheap clear improvement | Change code. Reply `Fixed in <short-sha>: <what>`. Resolve after the push. |
| **Decline** | False positive, conflicts with repo conventions, out of scope, or a repeat of an already-declined point | Reply `Not changing: <concrete reason>` (for a repeat: `Not changing: already addressed in round k — <reason>`). Resolve. |
| **Ask user** | Product or behaviour decision, or a scope expansion | Leave unresolved, with no reply. Tell the user right away, and keep handling the other comments. If the same point comes back in a later round, it stays one pending question. When the user answers, apply the answer as a Fix or Decline. |

Outdated threads are triaged too: check whether the latest code still has the issue.

**5. Push.** This step depends on whether the round changed any files.
- **Files changed:** run the fast checks again. Make one commit per round (e.g. `Address Copilot review (round k)`) and push normally. Do not force-push, which detaches the review anchors.
- **Nothing changed** (no Fix verdicts and no local edits): skip the commit and push.

Either way, post the replies and resolve the threads.

**6. Converged?** Stop when the first of these is true:
1. **Converged:** the Copilot review for the current head has no comment that gets a **Fix** verdict. That covers zero comments, and it covers comments that are all declined repeats or nits. Pending **Ask user** items do not block convergence; list them in the report.
2. **Round cap** reached. Fixes from the final round are still pushed, and the report marks them "not reviewed by Copilot".
3. **Copilot unavailable:** not enabled, or two timeouts or errors in a row.

If none of these holds, go back to step 1 with the new head SHA.

## Replies

- Never write `@copilot` in a reply or a commit message. It can summon the Copilot coding agent, which pushes commits to the branch.
- Copilot does not answer replies. The replies are for human reviewers, so keep them short and concrete.

## Final report (in the user's language)

1. PR URL.
2. Rounds run, and which stop condition ended the loop.
3. Per round: one line per comment, written as `fixed (sha)`, `declined (reason)` or `needs your decision`.
4. CI state (`gh pr checks <n>` or `get_check_runs`) and what still blocks the merge, such as a required human approval. Copilot's review never counts as an approval.

Do not merge unless the user explicitly asked you to.

## Common mistakes

- Accepting an older Copilot review as this round's result. Match on `commit_id` == head *and* `id` > the baseline. The head check alone still accepts a failed review when you re-request on the same commit.
- Pushing while a review is pending. The review then lands on a stale SHA, and the round is wasted.
- Applying every suggestion blindly. Copilot produces false positives, so verify each one against the code.
- Re-arguing a declined point every round. A repeat gets **Decline** ("already addressed in round k") and does not block convergence.
- Requesting Copilot twice when a ruleset already re-requests it on push.
- Forgetting earlier rounds. Without the ledger, you cannot recognise repeats and the report is incomplete.
