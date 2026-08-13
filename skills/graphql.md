# Projects v2 GraphQL reference

Everything here goes through `gh api graphql`. Projects v2 has no REST surface
worth using, and MCP/built-in project tools target Classic and 404 against v2.

Variable convention: `-f` for strings, `-F` for numbers, booleans, and null.

## Discover

```bash
# Org-owned projects
gh api graphql -f query='query($org:String!){
  organization(login:$org){ projectsV2(first:30){ nodes { id number title } } } }' \
  -f org="$ORG"

# User-owned (a common reason an org query comes back empty)
gh api graphql -f query='{ viewer { projectsV2(first:20){ nodes { id number title } } } }'

# Repo-linked
gh api graphql -f query='query($o:String!,$n:String!){
  repository(owner:$o,name:$n){ projectsV2(first:20){ nodes { id number title } } } }' \
  -f o="$ORG" -f n=REPO
```

## Field and option IDs

Use `scripts/board-ids.sh`. Mutations take node IDs — there is no way to set a
field by name. Single-select values need the *option* ID, not the label.

ID prefixes are a useful sanity check:

| Prefix | Thing |
|---|---|
| `PVT_` | project |
| `PVTF_` | field |
| `PVTSSF_` | single-select field |
| `PVTIF_` | iteration field |
| `PVTI_` | project item |
| `I_` | issue |

## Read items

See `scripts/board-fetch.sh` for the paginated version. The shape:

```graphql
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
            ... on Issue {
              number title url state updatedAt
              repository { name isArchived }
              labels(first:20) { nodes { name } }
              assignees(first:5) { nodes { login } }
            }
            ... on DraftIssue { title createdAt }
            ... on PullRequest { number title url state merged }
          }
        }
      }
    }
  }
}
```

`fieldValues` returns a union — every branch needs an inline fragment or you get
empty objects with no error. A `content` of `null`/missing `__typename` means the
item's repo was deleted, transferred, or is outside your token's visibility.

## Write

Single-select (Status, Class):

```bash
gh api graphql -f query='
mutation($p:ID!, $i:ID!, $f:ID!, $o:String!) {
  updateProjectV2ItemFieldValue(input:{
    projectId:$p itemId:$i fieldId:$f value:{ singleSelectOptionId:$o }
  }) { projectV2Item { id } }
}' -f p=PVT_xxx -f i=PVTI_xxx -f f=PVTSSF_xxx -f o=OPTION_ID
```

Number (Estimate) — note `-F` so it's sent as a number:

```bash
gh api graphql -f query='
mutation($p:ID!, $i:ID!, $f:ID!, $v:Float!) {
  updateProjectV2ItemFieldValue(input:{
    projectId:$p itemId:$i fieldId:$f value:{ number:$v }
  }) { projectV2Item { id } }
}' -f p=PVT_xxx -f i=PVTI_xxx -f f=PVTF_xxx -F v=3
```

Iteration:

```graphql
value:{ iterationId: "ITERATION_ID" }
```

Clear a field: `clearProjectV2ItemFieldValue(input:{projectId, itemId, fieldId})`.

## Add and convert

```bash
# Issue node ID first
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){
  repository(owner:$o,name:$r){ issue(number:$n){ id } } }' \
  -f o="$ORG" -f r=REPO -F n=123

# Add to board
gh api graphql -f query='
mutation($p:ID!, $c:ID!) {
  addProjectV2ItemById(input:{projectId:$p contentId:$c}) { item { id } }
}' -f p=PVT_xxx -f c=I_xxx
```

Draft → real issue:

```bash
gh api graphql -f query='
mutation($i:ID!, $r:ID!) {
  convertProjectV2DraftIssueItemToIssue(input:{itemId:$i repositoryId:$r}) {
    item { id } }
}' -f i=PVTI_xxx -f r=REPO_NODE_ID
```

Archive (does not delete): `archiveProjectV2Item(input:{projectId, itemId})`.

## What has no API

Do not attempt these — they're UI-only, and no amount of query shaping will
change that:

- Creating or configuring **views** (filters, grouping, sorting, layout)
- Creating **iteration fields** (single-select, number, date, text only)
- Configuring **built-in workflows**, including auto-add

Board setup therefore ends with manual UI steps. Capture them once by marking
the project as a template, so copies inherit views and fields.

## Gotchas

- Empty results with no error → missing `project` scope, SAML SSO not
  authorized, or wrong owner type. Check in that order.
- `GITHUB_TOKEN` in Actions **cannot** read Projects v2. Needs a fine-grained
  PAT or GitHub App token with org Projects read/write.
- GraphQL rate limiting is point-based, not request-based; deep pagination over
  a large board burns points fast. Sleep between pages.
- `updateProjectV2ItemFieldValue` on a single-select updates the data but has
  been reported not to refresh board-view grouping order in all cases. If a card
  looks like it didn't move, re-query before assuming the mutation failed.
