#!/usr/bin/env bash
# List unresolved review threads on a PR that were started by Copilot.
#
# Usage: bash copilot-threads.sh <pr-number>
#
# Prints one JSON object per line:
#   {"thread_id","comment_id","path","line","outdated","replies","body"}
# thread_id  -> GraphQL node id, for resolveReviewThread
# comment_id -> REST id of the root comment, for replying
# replies    -> number of comments after the root (>0 means someone already answered)
set -euo pipefail

pr="${1:?usage: copilot-threads.sh <pr-number>}"
owner="$(gh repo view --json owner -q .owner.login)"
name="$(gh repo view --json name -q .name)"

gh api graphql --paginate \
  -F owner="$owner" -F name="$name" -F pr="$pr" \
  -f query='
query($owner: String!, $name: String!, $pr: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 1) {
            totalCount
            nodes { databaseId body author { login } }
          }
        }
      }
    }
  }
}' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved | not)
    | select(.comments.nodes[0].author.login | . == "copilot-pull-request-reviewer")
    | {thread_id: .id,
       comment_id: .comments.nodes[0].databaseId,
       path, line,
       outdated: .isOutdated,
       replies: (.comments.totalCount - 1),
       body: .comments.nodes[0].body}
    | @json'
