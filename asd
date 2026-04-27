version: v1.1.0

# These steps run sequentially. Step 1 runs on whatever pool the task is invoked with;
# we'll invoke once with no agent pool (public) for bootstrap+base, then a separate
# task for the variants on the agent pool. See "How to run it" below.

steps:
  # --- BOOTSTRAP: public tools, no internal config ---
  - id: build-bootstrap
    build: >
      -t {{.Run.Registry}}/runner-images/bootstrap:{{.Run.ID}}
      -t {{.Run.Registry}}/runner-images/bootstrap:latest
      -f runner-images/bootstrap/Dockerfile
      runner-images/bootstrap

  - id: push-bootstrap
    push:
      - {{.Run.Registry}}/runner-images/bootstrap:{{.Run.ID}}
      - {{.Run.Registry}}/runner-images/bootstrap:latest
    when: ["build-bootstrap"]

  # --- BASE: applies certs, JFrog config, internal apt sources ---
  - id: build-base
    build: >
      -t {{.Run.Registry}}/runner-images/base:{{.Run.ID}}
      -t {{.Run.Registry}}/runner-images/base:latest
      --build-arg BOOTSTRAP_TAG={{.Run.ID}}
      --build-arg REGISTRY={{.Run.Registry}}
      -f runner-images/base/Dockerfile
      .
    when: ["push-bootstrap"]

  - id: push-base
    push:
      - {{.Run.Registry}}/runner-images/base:{{.Run.ID}}
      - {{.Run.Registry}}/runner-images/base:latest
    when: ["build-base"]

  # --- VARIANTS: parallel-able, all FROM base ---
  - id: build-dotnet6
    build: >
      -t {{.Run.Registry}}/runner-images/dotnet6:{{.Run.ID}}
      -t {{.Run.Registry}}/runner-images/dotnet6:latest
      --build-arg BASE_TAG={{.Run.ID}}
      --build-arg REGISTRY={{.Run.Registry}}
      -f runner-images/dotnet6/Dockerfile
      .
    when: ["push-base"]

  - id: build-dotnet8
    build: >
      -t {{.Run.Registry}}/runner-images/dotnet8:{{.Run.ID}}
      -t {{.Run.Registry}}/runner-images/dotnet8:latest
      --build-arg BASE_TAG={{.Run.ID}}
      --build-arg REGISTRY={{.Run.Registry}}
      -f runner-images/dotnet8/Dockerfile
      .
    when: ["push-base"]

  - id: build-dotnet10
    build: >
      -t {{.Run.Registry}}/runner-images/dotnet10:{{.Run.ID}}
      -t {{.Run.Registry}}/runner-images/dotnet10:latest
      --build-arg BASE_TAG={{.Run.ID}}
      --build-arg REGISTRY={{.Run.Registry}}
      -f runner-images/dotnet10/Dockerfile
      .
    when: ["push-base"]

  - id: push-variants
    push:
      - {{.Run.Registry}}/runner-images/dotnet6:{{.Run.ID}}
      - {{.Run.Registry}}/runner-images/dotnet6:latest
      - {{.Run.Registry}}/runner-images/dotnet8:{{.Run.ID}}
      - {{.Run.Registry}}/runner-images/dotnet8:latest
      - {{.Run.Registry}}/runner-images/dotnet10:{{.Run.ID}}
      - {{.Run.Registry}}/runner-images/dotnet10:latest
    when: ["build-dotnet6", "build-dotnet8", "build-dotnet10"]
