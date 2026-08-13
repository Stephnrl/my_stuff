#!/usr/bin/env bash
# Read-only invariant checks. Prints findings, changes nothing.
set -euo pipefail

source "$HOME/.copilot/board.env"
WIP_LIMIT="${WIP_LIMIT:-8}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ITEMS=$(bash "$DIR/board-fetch.sh")

status() { echo "$1" | jq -r '[.fieldValues.nodes[]? | select(.field.name=="Status") | .name][0] // "unset"'; }

echo "$ITEMS" | jq -r --argjson wip "$WIP_LIMIT" '
def st: [.fieldValues.nodes[]? | select(.field.name=="Status") | .name][0];
def age: ((now - ((.content.updatedAt // .updatedAt) | fromdateiso8601)) / 86400 | floor);
def key: if .content.repository then "\(.content.repository.name)#\(.content.number)" else (.content.title // .id) end;

[ .[] | select(.isArchived != true) ] as $live

| ( [ $live[] | select(.content.__typename=="Issue" and .content.state=="CLOSED" and (st != "Done"))
      | "BLOCK closed-not-done   \(key)  status=\(st // "unset")" ] )
+ ( [ $live[] | select(.content.__typename=="Issue" and .content.state=="OPEN" and st=="Done")
      | "WARN  done-still-open   \(key)" ] )
+ ( [ $live[] | select(.content.__typename==null)
      | "BLOCK dead-reference    \(.id)" ] )
+ ( [ $live[] | select(.content.__typename=="DraftIssue" and age > 14)
      | "WARN  stranded-draft    \(key)  \(age)d old" ] )
+ ( [ $live[] | select(st == null)
      | "WARN  no-status         \(key)" ] )
+ ( [ $live[] | select(st=="Blocked" and ([.content.labels.nodes[]?.name] | index("blocked") | not))
      | "WARN  blocked-no-reason \(key)" ] )
+ ( [ $live[] | select((st=="In Progress" or st=="In Review") and ((.content.assignees.nodes // []) | length) == 0)
      | "WARN  unassigned-active \(key)  status=\(st)" ] )
+ ( [ $live[] | select(st=="In Progress" and age > 5) | "INFO  stale-progress    \(key)  \(age)d" ] )
+ ( [ $live[] | select(st=="In Review"   and age > 2) | "INFO  stale-review      \(key)  \(age)d" ] )
+ ( [ $live[] | select(.content.__typename=="Issue" and .content.state=="OPEN"
        and ([.content.labels.nodes[]?.name | select(startswith("type:"))] | length) == 0)
      | "INFO  untyped           \(key)" ] )
+ ( if ([ $live[] | select(st=="In Progress") ] | length) > $wip
    then [ "WARN  wip-over-limit    \([ $live[] | select(st=="In Progress") ] | length) in progress, limit \($wip)" ]
    else [] end )
| .[]
' | sort || echo "No findings."
