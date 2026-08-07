gh auth login --scopes read:enterprise,admin:enterprise

gh api graphql -f enterprise=YOUR-ENTERPRISE-SLUG -f query='
  query($enterprise: String!, $cursor: String) {
    enterprise(slug: $enterprise) {
      ownerInfo {
        samlIdentityProvider {
          externalIdentities(first: 100, after: $cursor) {
            pageInfo { hasNextPage endCursor }
            nodes { guid samlIdentity { nameId } user { login } }
          }
        }
      }
    }
  }'


gh api graphql --paginate --slurp \
  -f enterprise=YOUR-ENTERPRISE-SLUG \
  -f query='...same query as above...' \
  | jq -r '.[].data.enterprise.ownerInfo.samlIdentityProvider.externalIdentities.nodes[]
           | select(.user.login != null)
           | [.samlIdentity.nameId, .user.login] | @tsv'
