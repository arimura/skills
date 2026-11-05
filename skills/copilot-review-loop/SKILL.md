---
name: copilot-review-loop
description: Use when asked to open a PR and loop GitHub Copilot code review until its feedback converges, or to run repeated Copilot review rounds on an existing PR ("Copilotレビューを収束するまで回して").
---

# Copilot Review Loop

Open (or reuse) a PR, draft or not, then repeat: request a Copilot review → wait for it → triage every finding → push fixes, reply, resolve. Stop when a review has nothing worth fixing, or after 5 rounds (the user may change the cap).

- **This round's review** is by `copilot-pull-request-reviewer[bot]` exactly (not `copilot-swe-agent`), on the commit you requested, and newer than the reviews that existed when you requested it. Do not push while waiting.
- **Read the review body.** Findings can appear only there (e.g. "previously missed issues"), even under a "No open issues" heading.
- **Triage** each finding against the code; Copilot is often wrong. Fix → push, reply, resolve. Decline → reply with the reason, resolve. Needs a product decision → leave it open and ask the user.
- **Drafts:** request Copilot explicitly every round, because automatic review skips drafts. Never mark the PR ready yourself.
- **Cost:** each review costs money (about $1.50 at default effort). Do not request beyond the cap.
- **Finish** with a report in the user's language: PR URL, rounds run and why the loop stopped, each finding's verdict. Do not merge.
