#!/usr/bin/env bash
# One-time setup: verify scopes, find the project, write ~/.copilot/board.env
set -euo pipefail

ENV_FILE="$HOME/.copilot/board.env"

echo "==> Checking gh auth"
if ! gh auth status >/dev/null 2>&1; then
  echo "Not logged in. Run: gh auth login" >&2
  exit 1
fi

if ! gh auth status 2>&1 | grep -qE "'(read:)?project'"; then
  echo "Missing project scope. Run:" >&2
  echo "  gh auth refresh -s project,read:project" >&2
  echo "(Enterprise Cloud with SAML: also SSO-authorize the token for the org.)" >&2
  exit 1
fi

read -rp "Org login: " ORG

echo "==> Org-owned Projects v2 in $ORG"
gh api graphql -f query='
query($org:String!){ organization(login:$org){
  projectsV2(first:30){ nodes { number title } } } }' \
  -f org="$ORG" \
  --jq '.data.organization.projectsV2.nodes[] | "  \(.number)\t\(.title)"' \
  || true

echo
echo "Nothing listed? The project may be user-owned. Check with:"
echo "  gh api graphql -f query='{viewer{projectsV2(first:20){nodes{number title}}}}'"
echo

read -rp "Project number: " PROJECT_NUMBER

mkdir -p "$HOME/.copilot"
cat > "$ENV_FILE" <<EOF
ORG=$ORG
PROJECT_NUMBER=$PROJECT_NUMBER
BOARD_URL=https://github.com/orgs/$ORG/projects/$PROJECT_NUMBER
WIP_LIMIT=8
STALE_IN_PROGRESS=5
STALE_IN_REVIEW=2
EOF

echo "==> Wrote $ENV_FILE"
echo "Next: bash ~/.copilot/skills/board-ops/scripts/board-ids.sh"
