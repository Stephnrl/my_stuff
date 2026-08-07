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
