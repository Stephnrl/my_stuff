ghe-logs-tail | egrep -i 'error|exception|elasticsearch|aqueduct|project|pull|release|disk|no space|readonly|timeout'


ghe-aqueduct status | jq '
  paths(scalars) as $p
  | select(($p | join(".") | test("queue|depth|active|failed|retry|dead|size|count"; "i")))
  | "\($p | join(".")) = \(getpath($p))"
'

ghe-aqueduct status | jq -r '
  .. | objects
  | to_entries[]
  | select(.key | test("queue|depth|size|count|active|failed|retry|dead"; "i"))
  | "\(.key): \(.value)"
' | sort
