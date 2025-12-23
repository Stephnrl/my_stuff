# ==============================================================================
# ARC Deployment Terraform Module
# ==============================================================================
# This module deploys GitHub Actions Runner Controller (ARC) to an AKS cluster
# using Helm. It handles:
# - Namespace creation
# - Kubernetes secrets for image pull and GitHub auth
# - Helm chart deployment
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11.0"
    }
  }
}

# ==============================================================================
# Local Variables
# ==============================================================================
locals {
  controller_namespace = var.controller_namespace
  runners_namespace    = var.runners_namespace

  common_labels = merge(var.common_labels, {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "arc"
  })

  # Determine which image pull secret to use
  image_pull_secret_name = var.jfrog_config.enabled ? var.jfrog_config.secret_name : null

  # Chart repository - using OCI registry
  chart_repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
}

# ==============================================================================
# Namespaces
# ==============================================================================
resource "kubernetes_namespace" "controller" {
  count = var.create_namespaces ? 1 : 0

  metadata {
    name   = local.controller_namespace
    labels = local.common_labels
  }
}

resource "kubernetes_namespace" "runners" {
  count = var.create_namespaces ? 1 : 0

  metadata {
    name   = local.runners_namespace
    labels = local.common_labels
  }
}

# ==============================================================================
# JFrog Image Pull Secrets
# ==============================================================================
resource "kubernetes_secret" "jfrog_pull_secret_controller" {
  count = var.jfrog_config.enabled ? 1 : 0

  metadata {
    name      = var.jfrog_config.secret_name
    namespace = local.controller_namespace
    labels    = local.common_labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.jfrog_config.server) = {
          username = var.jfrog_config.username
          password = var.jfrog_config.password
          auth     = base64encode("${var.jfrog_config.username}:${var.jfrog_config.password}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.controller]
}

resource "kubernetes_secret" "jfrog_pull_secret_runners" {
  count = var.jfrog_config.enabled ? 1 : 0

  metadata {
    name      = var.jfrog_config.secret_name
    namespace = local.runners_namespace
    labels    = local.common_labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.jfrog_config.server) = {
          username = var.jfrog_config.username
          password = var.jfrog_config.password
          auth     = base64encode("${var.jfrog_config.username}:${var.jfrog_config.password}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.runners]
}

# ==============================================================================
# GitHub Authentication Secret
# ==============================================================================
resource "kubernetes_secret" "github_auth" {
  metadata {
    name      = var.github_auth.secret_name
    namespace = local.runners_namespace
    labels    = local.common_labels
  }

  data = var.github_auth.use_app ? {
    github_app_id              = var.github_auth.app_id
    github_app_installation_id = var.github_auth.app_installation_id
    github_app_private_key     = var.github_auth.app_private_key
  } : {
    github_token = var.github_auth.pat_token
  }

  depends_on = [kubernetes_namespace.runners]
}

# ==============================================================================
# ARC Controller Helm Release
# ==============================================================================
resource "helm_release" "arc_controller" {
  count = var.deploy_controller ? 1 : 0

  name       = var.controller_release_name
  namespace  = local.controller_namespace
  repository = local.chart_repository
  chart      = "gha-runner-scale-set-controller"
  version    = var.chart_version

  create_namespace = false
  wait             = true
  timeout          = var.helm_timeout

  # Image configuration
  dynamic "set" {
    for_each = var.controller_image.repository != "" ? [1] : []
    content {
      name  = "image.repository"
      value = var.controller_image.repository
    }
  }

  dynamic "set" {
    for_each = var.controller_image.tag != "" ? [1] : []
    content {
      name  = "image.tag"
      value = var.controller_image.tag
    }
  }

  set {
    name  = "image.pullPolicy"
    value = var.controller_image.pull_policy
  }

  # Image pull secrets
  dynamic "set" {
    for_each = local.image_pull_secret_name != null ? [1] : []
    content {
      name  = "imagePullSecrets[0].name"
      value = local.image_pull_secret_name
    }
  }

  # Resources
  set {
    name  = "resources.requests.cpu"
    value = var.controller_resources.requests.cpu
  }

  set {
    name  = "resources.requests.memory"
    value = var.controller_resources.requests.memory
  }

  set {
    name  = "resources.limits.cpu"
    value = var.controller_resources.limits.cpu
  }

  set {
    name  = "resources.limits.memory"
    value = var.controller_resources.limits.memory
  }

  depends_on = [
    kubernetes_namespace.controller,
    kubernetes_secret.jfrog_pull_secret_controller
  ]
}

# ==============================================================================
# Runner Scale Set Helm Release
# ==============================================================================
resource "helm_release" "arc_runner_scale_set" {
  name       = var.runner_release_name
  namespace  = local.runners_namespace
  repository = local.chart_repository
  chart      = "gha-runner-scale-set"
  version    = var.chart_version

  create_namespace = false
  wait             = true
  timeout          = var.helm_timeout

  # GitHub configuration
  set {
    name  = "githubConfigUrl"
    value = var.github_config.url
  }

  set {
    name  = "githubConfigSecret"
    value = var.github_auth.secret_name
  }

  dynamic "set" {
    for_each = var.github_config.runner_group != "" ? [1] : []
    content {
      name  = "runnerGroup"
      value = var.github_config.runner_group
    }
  }

  # Runner Scale Set name (used in runs-on)
  set {
    name  = "runnerScaleSetName"
    value = var.runner_scale_set_name
  }

  # Scaling configuration
  set {
    name  = "minRunners"
    value = var.runner_scaling.min_runners
  }

  set {
    name  = "maxRunners"
    value = var.runner_scaling.max_runners
  }

  # Container mode
  dynamic "set" {
    for_each = var.container_mode != "none" ? [1] : []
    content {
      name  = "containerMode.type"
      value = var.container_mode
    }
  }

  # Runner image
  set {
    name  = "template.spec.containers[0].name"
    value = "runner"
  }

  set {
    name  = "template.spec.containers[0].image"
    value = "${var.runner_image.repository}:${var.runner_image.tag}"
  }

  set {
    name  = "template.spec.containers[0].imagePullPolicy"
    value = var.runner_image.pull_policy
  }

  # Runner resources
  set {
    name  = "template.spec.containers[0].resources.requests.cpu"
    value = var.runner_resources.requests.cpu
  }

  set {
    name  = "template.spec.containers[0].resources.requests.memory"
    value = var.runner_resources.requests.memory
  }

  set {
    name  = "template.spec.containers[0].resources.limits.cpu"
    value = var.runner_resources.limits.cpu
  }

  set {
    name  = "template.spec.containers[0].resources.limits.memory"
    value = var.runner_resources.limits.memory
  }

  # Image pull secrets for runners
  dynamic "set" {
    for_each = local.image_pull_secret_name != null ? [1] : []
    content {
      name  = "template.spec.imagePullSecrets[0].name"
      value = local.image_pull_secret_name
    }
  }

  # Controller service account reference
  dynamic "set" {
    for_each = var.deploy_controller ? [1] : []
    content {
      name  = "controllerServiceAccount.namespace"
      value = local.controller_namespace
    }
  }

  dynamic "set" {
    for_each = var.deploy_controller ? [1] : []
    content {
      name  = "controllerServiceAccount.name"
      value = "${var.controller_release_name}-gha-runner-scale-set-controller"
    }
  }

  depends_on = [
    kubernetes_namespace.runners,
    kubernetes_secret.jfrog_pull_secret_runners,
    kubernetes_secret.github_auth,
    helm_release.arc_controller
  ]
}
