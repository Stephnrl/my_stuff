      - name: Setup GitVersion
        uses: gittools/actions/gitversion/setup@v4.5.0
        with:
          versionSpec: '6.0.5'

      - name: Calculate GitVersion
        id: gitversion
        uses: gittools/actions/gitversion/execute@v4.5.0
        with:
          useConfigFile: true

      - name: Show version
        run: |
          echo "SemVer: ${{ steps.gitversion.outputs.semVer }}"
          echo "FullSemVer: ${{ steps.gitversion.outputs.fullSemVer }}"
          echo "MajorMinorPatch: ${{ steps.gitversion.outputs.majorMinorPatch }}"


# GitVersion.yml
workflow: GitHubFlow/v1
mode: Mainline
tag-prefix: '[vV]?'

next-version: 1.0.0

branches:
  main:
    regex: ^main$
    increment: Patch
    is-main-branch: true

ignore:
  sha: []
