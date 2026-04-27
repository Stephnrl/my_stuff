name: Build Runner Images

on:
  push:
    branches: [main]
    paths:
      - 'runner-images/**'
      - 'shared/**'
      - 'acr-task.yml'
      - '.github/workflows/runner-images.yml'
  schedule:
    - cron: '0 6 * * 1'   # weekly Monday 06:00 UTC for module/CVE refresh
  workflow_dispatch:

env:
  ACR_NAME: myregistry
  AGENT_POOL: my-vnet-pool   # only used if you split

jobs:
  build-images:
    runs-on: self-hosted     # your existing self-hosted runner
    steps:
      - uses: actions/checkout@v4

      - name: Azure login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Run ACR multi-step task
        run: |
          az acr run \
            --registry $ACR_NAME \
            --file acr-task.yml \
            .
