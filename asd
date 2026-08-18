name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.11", "3.12"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      - name: Install package
        run: pip install -e ".[dev]"
      - name: Run tests
        run: python -m pytest tests/ -v

  lint-workflows:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate workflow YAML parses
        # A column-0 heredoc terminator inside a `run: |` block silently
        # terminates the YAML block scalar and produces an unparseable file.
        # This repo shipped exactly that bug once; the check stays.
        run: |
          set -euo pipefail
          python -c "
          import sys, yaml, pathlib
          bad = []
          for f in list(pathlib.Path('.github/workflows').glob('*.yml')) + [pathlib.Path('action.yml')]:
              try:
                  yaml.safe_load(f.read_text())
                  print(f'OK   {f}')
              except Exception as e:
                  bad.append(f); print(f'FAIL {f}: {e}')
          sys.exit(1 if bad else 0)
          "
      - name: actionlint
        uses: raven-actions/actionlint@v2
        with:
          fail-on-error: true

  validate-exceptions:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install -e .
      # Fails the PR on a malformed or over-long exception before it can
      # silently become "no exceptions" at gate time.
      - run: poam validate-exceptions --exceptions exceptions/

  terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform fmt -check -recursive
      - run: terraform init -backend=false
      - run: terraform validate
