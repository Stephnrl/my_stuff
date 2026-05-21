name: Validate Runner Image

on:
  repository_dispatch:
    types: [validate-runner-image]

permissions:
  contents: read

concurrency:
  group: validate-runner-${{ github.event.client_payload.environment }}
  cancel-in-progress: false

jobs:
  validate:
    name: Validate runner image
    runs-on: ${{ github.event.client_payload.runner_label }}

    steps:
      - name: Print runner context
        run: |
          echo "Runner name: $RUNNER_NAME"
          echo "Runner OS: $RUNNER_OS"
          echo "Image version: ${{ github.event.client_payload.image_tag }}"
          uname -a || true

      - name: Validate core tooling
        shell: bash
        run: |
          set -euo pipefail

          command -v az
          command -v aws
          command -v terraform
          command -v kubectl
          command -v helm
          command -v python3
          command -v node
          command -v pwsh

          az version
          aws --version
          terraform version
          kubectl version --client=true
          helm version
          python3 --version
          node --version
          pwsh --version

      - name: Validate internal certificate trust
        shell: bash
        run: |
          set -euo pipefail
          # Replace with internal endpoints that prove cert trust and routing.
          curl -fsS https://your-internal-jfrog.example.com/api/system/ping

      - name: Validate package mirrors
        shell: bash
        run: |
          set -euo pipefail
          # Keep this lightweight. Goal is to prove internal mirrors are reachable.
          python3 -m pip config list || true
          npm config get registry || true

      - name: Validate Kubernetes access is not accidentally present
        shell: bash
        run: |
          set -euo pipefail
          # Optional negative control: runner image should have tools,
          # but not broad cluster/admin credentials baked in.
          test ! -f ~/.kube/config || {
            echo "Unexpected kubeconfig found on runner image"
            exit 1
          }
