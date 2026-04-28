version: v1.1.0

# Single task orchestrating: bootstrap → base → variants (parallel) →
# smoke tests (parallel) → functional tests (parallel) → promote to :latest.
#
# Promotion only happens if all tests pass. Failures leave :candidate-{run-id}
# in ACR for debugging but never touch :latest.

stepTimeout: 3600

steps:
  # =========================================================================
  # STAGE 1: BOOTSTRAP (public sources, no internal config)
  # =========================================================================
  - id: build-bootstrap
    build: >
      -t {{.Run.Registry}}/runner-images/bootstrap:{{.Run.ID}}
      -f runner-images/bootstrap/Dockerfile
      runner-images/bootstrap

  - id: push-bootstrap
    push:
      - {{.Run.Registry}}/runner-images/bootstrap:{{.Run.ID}}
    when: ["build-bootstrap"]

  - id: smoke-bootstrap
    cmd: >
      {{.Run.Registry}}/runner-images/bootstrap:{{.Run.ID}}
      bash -c "
        set -e;
        echo '=== Bootstrap smoke ===';
        node --version;
        npm --version;
        java -version 2>&1;
        packer version;
        eksctl version;
        helm version --short;
        kubectl version --client;
        terraform version;
        tfenv list;
        pwsh -c 'Get-Module Az,Pester -ListAvailable | Select-Object Name, Version';
        echo 'Bootstrap smoke OK'
      "
    when: ["push-bootstrap"]

  # =========================================================================
  # STAGE 2: BASE (apply internal certs and JFrog config)
  # =========================================================================
  - id: build-base
    build: >
      -t {{.Run.Registry}}/runner-images/base:{{.Run.ID}}
      --build-arg REGISTRY={{.Run.Registry}}
      --build-arg BOOTSTRAP_TAG={{.Run.ID}}
      -f runner-images/base/Dockerfile
      .
    when: ["smoke-bootstrap"]

  - id: push-base
    push:
      - {{.Run.Registry}}/runner-images/base:{{.Run.ID}}
    when: ["build-base"]

  - id: smoke-base
    cmd: >
      {{.Run.Registry}}/runner-images/base:{{.Run.ID}}
      bash -c "
        set -e;
        echo '=== Base smoke: certs and config ===';
        test -f /etc/ssl/certs/ca-certificates.crt && echo 'CA bundle present';
        test -s /etc/npmrc && echo '.npmrc present';
        test -s /etc/terraformrc && echo '.terraformrc present';
        test -s /etc/pip.conf && echo 'pip.conf present';
        echo '=== Registry config ===';
        npm config get registry | grep -q jfrog && echo 'npm → JFrog OK' || (echo 'npm not pointing at JFrog' && exit 1);
        echo '=== JFrog reachability ===';
        curl -fsS --max-time 10 https://mycorp.jfrog.io/artifactory/api/system/ping && echo 'JFrog reachable';
        echo 'Base smoke OK'
      "
    when: ["push-base"]

  # =========================================================================
  # STAGE 3: VARIANTS (parallel — share the same `when` on smoke-base)
  # =========================================================================
  - id: build-dotnet6
    build: >
      -t {{.Run.Registry}}/runner-images/dotnet6:{{.Run.ID}}
      --build-arg REGISTRY={{.Run.Registry}}
      --build-arg BASE_TAG={{.Run.ID}}
      -f runner-images/dotnet6/Dockerfile
      .
    when: ["smoke-base"]

  - id: build-dotnet8
    build: >
      -t {{.Run.Registry}}/runner-images/dotnet8:{{.Run.ID}}
      --build-arg REGISTRY={{.Run.Registry}}
      --build-arg BASE_TAG={{.Run.ID}}
      -f runner-images/dotnet8/Dockerfile
      .
    when: ["smoke-base"]

  - id: build-dotnet10
    build: >
      -t {{.Run.Registry}}/runner-images/dotnet10:{{.Run.ID}}
      --build-arg REGISTRY={{.Run.Registry}}
      --build-arg BASE_TAG={{.Run.ID}}
      -f runner-images/dotnet10/Dockerfile
      .
    when: ["smoke-base"]

  - id: push-variants
    push:
      - {{.Run.Registry}}/runner-images/dotnet6:{{.Run.ID}}
      - {{.Run.Registry}}/runner-images/dotnet8:{{.Run.ID}}
      - {{.Run.Registry}}/runner-images/dotnet10:{{.Run.ID}}
    when: ["build-dotnet6", "build-dotnet8", "build-dotnet10"]

  # =========================================================================
  # STAGE 4: SMOKE TESTS (parallel, per variant)
  # =========================================================================
  - id: smoke-dotnet6
    cmd: >
      {{.Run.Registry}}/runner-images/dotnet6:{{.Run.ID}}
      bash -c "
        set -e;
        dotnet --list-sdks | grep -q '^6\.' && echo '.NET 6 SDK present';
        dotnet --list-runtimes;
        echo 'dotnet6 smoke OK'
      "
    when: ["push-variants"]

  - id: smoke-dotnet8
    cmd: >
      {{.Run.Registry}}/runner-images/dotnet8:{{.Run.ID}}
      bash -c "
        set -e;
        dotnet --list-sdks | grep -q '^8\.' && echo '.NET 8 SDK present';
        dotnet --list-runtimes;
        echo 'dotnet8 smoke OK'
      "
    when: ["push-variants"]

  - id: smoke-dotnet10
    cmd: >
      {{.Run.Registry}}/runner-images/dotnet10:{{.Run.ID}}
      bash -c "
        set -e;
        dotnet --list-sdks | grep -q '^10\.' && echo '.NET 10 SDK present';
        dotnet --list-runtimes;
        echo 'dotnet10 smoke OK'
      "
    when: ["push-variants"]

  # =========================================================================
  # STAGE 5: FUNCTIONAL TESTS (parallel, real workload through JFrog)
  # =========================================================================
  - id: functional-dotnet6
    cmd: >
      {{.Run.Registry}}/runner-images/dotnet6:{{.Run.ID}}
      bash -c "
        set -e;
        cd /workspace/runner-images/test-fixtures/hello-dotnet6 && dotnet build;
        cd /workspace/runner-images/test-fixtures/hello-npm     && npm install;
        cd /workspace/runner-images/test-fixtures/hello-tf      && terraform init -backend=false;
        echo 'dotnet6 functional OK'
      "
    when: ["smoke-dotnet6"]

  - id: functional-dotnet8
    cmd: >
      {{.Run.Registry}}/runner-images/dotnet8:{{.Run.ID}}
      bash -c "
        set -e;
        cd /workspace/runner-images/test-fixtures/hello-dotnet8 && dotnet build;
        cd /workspace/runner-images/test-fixtures/hello-npm     && npm install;
        cd /workspace/runner-images/test-fixtures/hello-tf      && terraform init -backend=false;
        echo 'dotnet8 functional OK'
      "
    when: ["smoke-dotnet8"]

  - id: functional-dotnet10
    cmd: >
      {{.Run.Registry}}/runner-images/dotnet10:{{.Run.ID}}
      bash -c "
        set -e;
        cd /workspace/runner-images/test-fixtures/hello-dotnet10 && dotnet build;
        cd /workspace/runner-images/test-fixtures/hello-npm      && npm install;
        cd /workspace/runner-images/test-fixtures/hello-tf       && terraform init -backend=false;
        echo 'dotnet10 functional OK'
      "
    when: ["smoke-dotnet10"]

  # =========================================================================
  # STAGE 6: PROMOTE (retag candidate → latest, only if everything passed)
  # =========================================================================
  - id: promote-bootstrap
    cmd: >
      mcr.microsoft.com/azure-cli az acr import
      --name {{.Run.Registry | replace ".azurecr.io" ""}}
      --source {{.Run.Registry}}/runner-images/bootstrap:{{.Run.ID}}
      --image runner-images/bootstrap:latest
      --force
    when: ["functional-dotnet6", "functional-dotnet8", "functional-dotnet10"]

  - id: promote-base
    cmd: >
      mcr.microsoft.com/azure-cli az acr import
      --name {{.Run.Registry | replace ".azurecr.io" ""}}
      --source {{.Run.Registry}}/runner-images/base:{{.Run.ID}}
      --image runner-images/base:latest
      --force
    when: ["promote-bootstrap"]

  - id: promote-dotnet6
    cmd: >
      mcr.microsoft.com/azure-cli az acr import
      --name {{.Run.Registry | replace ".azurecr.io" ""}}
      --source {{.Run.Registry}}/runner-images/dotnet6:{{.Run.ID}}
      --image runner-images/dotnet6:latest
      --force
    when: ["promote-base"]

  - id: promote-dotnet8
    cmd: >
      mcr.microsoft.com/azure-cli az acr import
      --name {{.Run.Registry | replace ".azurecr.io" ""}}
      --source {{.Run.Registry}}/runner-images/dotnet8:{{.Run.ID}}
      --image runner-images/dotnet8:latest
      --force
    when: ["promote-base"]

  - id: promote-dotnet10
    cmd: >
      mcr.microsoft.com/azure-cli az acr import
      --name {{.Run.Registry | replace ".azurecr.io" ""}}
      --source {{.Run.Registry}}/runner-images/dotnet10:{{.Run.ID}}
      --image runner-images/dotnet10:latest
      --force
    when: ["promote-base"]
