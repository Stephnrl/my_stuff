version: v1.1.0

steps:
  - id: build-bootstrap
    build: >
      -t {{.Run.Registry}}/runner-images/bootstrap:{{.Run.ID}}
      -t {{.Run.Registry}}/runner-images/bootstrap:candidate
      --cache-from={{.Run.Registry}}/runner-images/bootstrap:latest
      -f runner-images/bootstrap/Dockerfile
      runner-images/bootstrap

  - id: push-bootstrap
    push:
      - {{.Run.Registry}}/runner-images/bootstrap:{{.Run.ID}}
      - {{.Run.Registry}}/runner-images/bootstrap:candidate
    when: ["build-bootstrap"]

  - id: smoke-bootstrap
    cmd: >
      {{.Run.Registry}}/runner-images/bootstrap:{{.Run.ID}}
      bash -c "
        set -e;
        node --version;
        pwsh -c 'Get-Module Az -ListAvailable';
        echo 'Bootstrap smoke OK'
      "
    when: ["push-bootstrap"]
