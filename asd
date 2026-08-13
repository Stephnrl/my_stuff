gh api graphql -f query='
query($org:String!) {
  organization(login:$org) {
    projectsV2(first:20) { nodes { id number title } }
  }
}' -f org=YOUR-ORG
