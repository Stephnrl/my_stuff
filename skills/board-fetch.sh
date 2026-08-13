#!/usr/bin/env bash
# Dump every board item as one JSON array on stdout. Paginates fully.
set -euo pipefail

source "$HOME/.copilot/board.env"

QUERY='
query($org:String!, $num:Int!, $cursor:String) {
  organization(login:$org) {
    projectV2(number:$num) {
      items(first:100, after:$cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isArchived updatedAt
          fieldValues(first:20) { nodes {
            ... on ProjectV2ItemFieldSingleSelectValue {
              name field { ... on ProjectV2SingleSelectField { name } } }
            ... on ProjectV2ItemFieldNumberValue {
              number field { ... on ProjectV2Field { name } } }
            ... on ProjectV2ItemFieldIterationValue {
              title field { ... on ProjectV2IterationField { name } } }
          } }
          content {
            __typename
            ... on DraftIssue { title createdAt }
            ... on Issue {
              number title url state updatedAt
              repository { name isArchived }
              labels(first:20) { nodes { name } }
              assignees(first:5) { nodes { login } }
            }
            ... on PullRequest { number title url state merged repository { name } }
          }
        }
      }
    }
  }
}'

CURSOR=null
echo "["
FIRST=1
while :; do
  RESP=$(gh api graphql -f query="$QUERY" -f org="$ORG" -F num="$PROJECT_NUMBER" \
           -F cursor="$CURSOR" 2>/dev/null)
  NODES=$(echo "$RESP" | jq -c '.data.organization.projectV2.items.nodes[]')
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    [ $FIRST -eq 0 ] && echo ","
    printf '%s' "$n"
    FIRST=0
  done <<< "$NODES"

  HAS_NEXT=$(echo "$RESP" | jq -r '.data.organization.projectV2.items.pageInfo.hasNextPage')
  [ "$HAS_NEXT" != "true" ] && break
  CURSOR=$(echo "$RESP" | jq -r '.data.organization.projectV2.items.pageInfo.endCursor')
  sleep 0.2
done
echo ""
echo "]"
