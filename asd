name: Build runner images

on:
  push:
    branches: [main]
    paths: ['runner-images/**']
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest   # GH-hosted — see "bootstrapping" note above
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Build and push runner images via ACR
        working-directory: runner-images
        run: |
          az acr run \
            --registry ${{ vars.ACR_NAME }} \
            --agent-pool ${{ vars.ACR_AGENT_POOL }} \
            --file acr-task.yaml \
            --set jfrogUrl=${{ vars.JFROG_PS_URL }} \
            .
