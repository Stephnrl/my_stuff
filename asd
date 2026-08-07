query {
  enterprise(slug: "YOUR-ENTERPRISE") {
    ownerInfo {
      samlIdentityProvider {
        externalIdentities(first: 100) {
          pageInfo { hasNextPage endCursor }
          nodes { guid samlIdentity { nameId } user { login } }
        }
      }
    }
  }
}
