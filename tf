name: Release

on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      # Version calculation
      - uses: gittools/actions/gitversion/setup@v4.2.0
        with:
          versionSpec: '6.x'
      
      - uses: gittools/actions/gitversion/execute@v4.2.0
        id: gitversion

      # Release management + changelog
      - uses: gittools/actions/gitreleasemanager/setup@v4.2.0
        with:
          versionSpec: '0.18.x'

      # Create release from milestone (generates notes from closed issues)
      - uses: gittools/actions/gitreleasemanager/create@v4.2.0
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          owner: ${{ github.repository_owner }}
          repository: ${{ github.event.repository.name }}
          milestone: v${{ steps.gitversion.outputs.majorMinorPatch }}

      # Export changelog to file
      - name: Export changelog
        run: |
          dotnet-gitreleasemanager export \
            --token ${{ secrets.GITHUB_TOKEN }} \
            -o '${{ github.repository_owner }}' \
            -r '${{ github.event.repository.name }}' \
            -f 'CHANGELOG.md'

      # Publish the release
      - uses: gittools/actions/gitreleasemanager/publish@v4.2.0
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          owner: ${{ github.repository_owner }}
          repository: ${{ github.event.repository.name }}
          tagName: v${{ steps.gitversion.outputs.majorMinorPatch }}
