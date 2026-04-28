version: v1.1.0

steps:
  - id: build-base
    build: >
      -t {{.Run.Registry}}/runner-images/base:{{.Run.ID}}
      --build-arg REGISTRY={{.Run.Registry}}
      --build-arg BOOTSTRAP_TAG={{.Values.bootstrap_tag}}
      -f runner-images/base/Dockerfile
      .

  - id: push-base
    push:
      - {{.Run.Registry}}/runner-images/base:{{.Run.ID}}
    when: ["build-base"]

  - id: smoke-base
    cmd: >
      {{.Run.Registry}}/runner-images/base:{{.Run.ID}}
      bash -c "
        set -e;
        npm config get registry | grep -q jfrog && echo 'npm → JFrog OK';
        curl -fsS --max-time 10 https://mycorp.jfrog.io/artifactory/api/system/ping && echo 'JFrog reachable';
        echo 'Base smoke OK'
      "
    when: ["push-base"]

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

  # smoke + functional + promote steps continue here, all on agent pool
  # ...
