# ---------------------------------------------------------------------------
# docker-bake.hcl — matrix build for ARC scale-set runners
# Usage:
#   docker buildx bake                     # builds both variants
#   docker buildx bake runner-dotnet80     # just .NET 8
#   docker buildx bake runner-dotnet100    # just .NET 10
#   docker buildx bake --push              # build + push to registry
# ---------------------------------------------------------------------------

variable "REGISTRY" {
  default = "ghcr.io/your-org"
}

variable "IMAGE_NAME" {
  default = "arc-runner"
}

variable "RUNNER_VERSION" {
  default = "latest"
}

variable "IMAGE_TAG" {
  # override in CI with e.g. the short sha or a date stamp
  default = "latest"
}

variable "PACKER_VERSION" {
  default = "1.14.3"
}

variable "TFENV_TERRAFORM_VERSIONS" {
  default = "0.12.31 1.5.7 1.8.5 1.9.8 1.10.5"
}

variable "TFENV_DEFAULT_VERSION" {
  default = "1.10.5"
}

# Toggle cache backend: "registry" for any OCI registry, "gha" when running
# inside GitHub Actions (needs docker/build-push-action or setup-buildx-action).
variable "CACHE_BACKEND" {
  default = "registry"
}

# ---------------------------------------------------------------------------
# Default target group
# ---------------------------------------------------------------------------
group "default" {
  targets = ["runner"]
}

# ---------------------------------------------------------------------------
# Shared base — inherit this for any additional variants later.
# ---------------------------------------------------------------------------
target "_common" {
  dockerfile = "Dockerfile"
  context    = "."
  platforms  = ["linux/amd64"]
  args = {
    RUNNER_VERSION           = RUNNER_VERSION
    PACKER_VERSION           = PACKER_VERSION
    TFENV_TERRAFORM_VERSIONS = TFENV_TERRAFORM_VERSIONS
    TFENV_DEFAULT_VERSION    = TFENV_DEFAULT_VERSION
  }
  labels = {
    "org.opencontainers.image.source"      = "https://github.com/your-org/your-repo"
    "org.opencontainers.image.description" = "Custom ARC scale-set runner"
  }
}

# ---------------------------------------------------------------------------
# Matrix target: one definition, two images.
# Targets materialise as runner-dotnet80 and runner-dotnet100.
# Cache-from lists BOTH variants so the shared early layers (apt, pwsh, az,
# terraform, packer, etc.) are a cache hit regardless of which you build.
# ---------------------------------------------------------------------------
target "runner" {
  inherits = ["_common"]
  name     = "runner-dotnet${replace(dotnet, ".", "")}"

  matrix = {
    dotnet = ["8.0", "10.0"]
  }

  args = {
    DOTNET_VERSION = dotnet
  }

  tags = [
    "${REGISTRY}/${IMAGE_NAME}:dotnet${replace(dotnet, ".", "")}-${IMAGE_TAG}",
    "${REGISTRY}/${IMAGE_NAME}:dotnet${replace(dotnet, ".", "")}-latest",
  ]

  cache-from = CACHE_BACKEND == "gha" ? [
    "type=gha,scope=dotnet${replace(dotnet, ".", "")}",
    "type=gha,scope=dotnet80",
    "type=gha,scope=dotnet100",
  ] : [
    "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:buildcache-dotnet${replace(dotnet, ".", "")}",
    "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:buildcache-dotnet80",
    "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:buildcache-dotnet100",
  ]

  cache-to = CACHE_BACKEND == "gha" ? [
    "type=gha,scope=dotnet${replace(dotnet, ".", "")},mode=max",
  ] : [
    "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:buildcache-dotnet${replace(dotnet, ".", "")},mode=max",
  ]
}
