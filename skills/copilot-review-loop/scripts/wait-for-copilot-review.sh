#!/usr/bin/env bash
# Wait until Copilot has submitted a review for the PR's current head commit.
#
# Usage: bash wait-for-copilot-review.sh <pr-number> [timeout-seconds] [interval-seconds]
#
# Exit codes:
#   0  review found  -> prints {"id","commit_id","submitted_at","state","body"} as JSON
#   2  timed out     -> no Copilot review for the head commit yet
#   1  usage / gh error
#
# Matching on commit_id == head SHA is what makes this safe: an older Copilot
# review (for a previous push) never counts as "the review we are waiting for".
set -euo pipefail

pr="${1:?usage: wait-for-copilot-review.sh <pr-number> [timeout-seconds] [interval-seconds]}"
timeout="${2:-900}"
interval="${3:-30}"

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
head="$(gh pr view "$pr" --json headRefOid -q .headRefOid)"
deadline=$(( $(date +%s) + timeout ))

# REST returns "copilot-pull-request-reviewer[bot]"; some surfaces show "Copilot".
filter='[.[]
  | select((.user.login | startswith("copilot-pull-request-reviewer")) or .user.login == "Copilot")
  | select(.commit_id == $head)]
  | last
  | if . == null then empty else {id, commit_id, submitted_at, state, body} end'

while :; do
  found="$(gh api --paginate "repos/$repo/pulls/$pr/reviews" \
    | jq -s 'add' | jq -c --arg head "$head" "$filter")"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    exit 0
  fi
  if (( $(date +%s) >= deadline )); then
    echo "timeout: no Copilot review for head $head after ${timeout}s" >&2
    exit 2
  fi
  sleep "$interval"
done
