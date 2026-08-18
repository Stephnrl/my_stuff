[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "container-security-gate"
version = "1.0.0"
description = "POA&M engine for container image security gating in Azure Government"
readme = "README.md"
requires-python = ">=3.11"
license = { text = "Proprietary" }

# Azure extras are optional on purpose: the local:// store driver must work on a
# runner with no Azure SDK installed (tests, dry runs, air-gapped debugging).
dependencies = [
    "openpyxl>=3.1,<4",
    "PyYAML>=6.0,<7",
]

[project.optional-dependencies]
azure = [
    "azure-identity>=1.19,<2",
    "azure-storage-blob>=12.24,<13",
    "azure-monitor-ingestion>=1.0,<2",
]
dev = [
    "pytest>=8.0",
    "pytest-cov>=5.0",
]

[project.scripts]
# Lets the action call `poam gate ...` instead of `python -m poam gate ...`
poam = "poam.cli:main"

[tool.setuptools]
packages = ["poam"]

[tool.setuptools.package-data]
poam = ["py.typed"]

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
addopts = "-q"

[tool.ruff]
line-length = 110
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP", "B"]
ignore = ["E501"]
