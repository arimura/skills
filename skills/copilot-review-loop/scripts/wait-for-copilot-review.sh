#!/usr/bin/env bash
# Wait for a *new* Copilot review on the PR head recorded at request time.
#
# Usage:
#   bash wait-for-copilot-review.sh baseline <pr-number>
#       Prints the id of the newest Copilot review on the PR (0 if none).
#       Run this BEFORE requesting a review.
#   bash wait-for-copilot-review.sh wait <pr-number> <baseline-id> <head-sha> [timeout-seconds] [interval-seconds]
#       Waits for a Copilot review with id > baseline-id and commit_id == head-sha.
#       head-sha is the PR head recorded when the review was requested.
#
# Exit codes for `wait`:
#   0  review found  -> prints {"id","commit_id","submitted_at","state","body"} as JSON
#   2  timed out     -> no new Copilot review for head-sha yet
#   3  head moved    -> someone else pushed during the wait; the round's target is stale
#   1  usage / gh error
#
# Both checks matter. The commit_id check rejects reviews of an older push. The
# id > baseline check rejects earlier reviews of the same commit, such as a
# failed review that you are re-requesting.
set -euo pipefail

for cmd in gh jq; do
  command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
done

usage() {
  sed -n '2,17p' "$0" >&2
  exit 1
}

mode="${1:-}"
pr="${2:-}"
[[ -n "$mode" && -n "$pr" ]] || usage

repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

# REST login of the Copilot code reviewer. "Copilot" is accepted as an alias
# seen in some payloads. Exact match only: /copilot/i would also catch the
# Copilot coding agent.
copilot_reviews() {
  gh api --paginate "repos/$repo/pulls/$pr/reviews" \
    | jq -s 'add // []
      | [.[] | select(.user.login == "copilot-pull-request-reviewer[bot]" or .user.login == "Copilot")]'
}

case "$mode" in
  baseline)
    copilot_reviews | jq '[.[].id] | max // 0'
    ;;
  wait)
    baseline="${3:?baseline-id required (run: wait-for-copilot-review.sh baseline <pr>)}"
    head="${4:?head-sha required: the PR head recorded when the review was requested}"
    timeout="${5:-900}"
    interval="${6:-30}"
    deadline=$(( $(date +%s) + timeout ))
    while :; do
      found="$(copilot_reviews | jq -c --arg head "$head" --argjson base "$baseline" '
        [.[] | select(.commit_id == $head and .id > $base)]
        | last
        | if . == null then empty else {id, commit_id, submitted_at, state, body} end')"
      # Check head drift before accepting a review too: a review of a commit
      # that is no longer the head is stale for this round.
      current="$(gh pr view "$pr" --json headRefOid -q .headRefOid)"
      if [[ "$current" != "$head" ]]; then
        echo "head moved: requested review for $head, PR head is now $current" >&2
        exit 3
      fi
      if [[ -n "$found" ]]; then
        printf '%s\n' "$found"
        exit 0
      fi
      if (( $(date +%s) >= deadline )); then
        echo "timeout: no new Copilot review (id > $baseline) for head $head after ${timeout}s" >&2
        exit 2
      fi
      sleep "$interval"
    done
    ;;
  *)
    usage
    ;;
esac
