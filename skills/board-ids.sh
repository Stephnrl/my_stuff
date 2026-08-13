#!/usr/bin/env bash
# Cache project / field / option / iteration node IDs. Mutations need IDs, not names.
set -euo pipefail

source "$HOME/.copilot/board.env"
OUT="$HOME/.copilot/board-ids.json"

gh api graphql -f query='
query($org:String!, $num:Int!) {
  organization(login:$org) {
    projectV2(number:$num) {
      id title
      fields(first:50) {
        nodes {
          ... on ProjectV2Field { id name dataType }
          ... on ProjectV2SingleSelectField {
            id name options { id name }
          }
          ... on ProjectV2IterationField {
            id name
            configuration {
              duration startDay
              iterations { id title startDate duration }
              completedIterations { id title }
            }
          }
        }
      }
    }
  }
}' -f org="$ORG" -F num="$PROJECT_NUMBER" --jq '.data.organization.projectV2' > "$OUT"

echo "==> $OUT"
jq -r '"project: \(.id)  (\(.title))", (.fields.nodes[] | select(.name) | "  \(.name)\t\(.id)")' "$OUT"
