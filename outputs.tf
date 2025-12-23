# ==============================================================================
# Outputs for ARC Deployment Module
# ==============================================================================

output "controller_namespace" {
  description = "Namespace where the ARC controller is deployed"
  value       = local.controller_namespace
}

output "runners_namespace" {
  description = "Namespace where the runners are deployed"
  value       = local.runners_namespace
}

output "runner_scale_set_name" {
  description = "Name of the runner scale set (use this in your workflow runs-on)"
  value       = var.runner_scale_set_name
}

output "controller_release_name" {
  description = "Helm release name of the controller"
  value       = var.deploy_controller ? helm_release.arc_controller[0].name : null
}

output "runner_release_name" {
  description = "Helm release name of the runner scale set"
  value       = helm_release.arc_runner_scale_set.name
}

output "chart_version" {
  description = "Version of the ARC Helm charts deployed"
  value       = var.chart_version
}

output "github_config_url" {
  description = "GitHub URL configured for the runners"
  value       = var.github_config.url
}

output "workflow_runs_on_example" {
  description = "Example of how to use these runners in a GitHub Actions workflow"
  value       = <<-EOT
    # Use this in your GitHub Actions workflow:
    jobs:
      build:
        runs-on: ${var.runner_scale_set_name}
        steps:
          - uses: actions/checkout@v4
          - run: echo "Running on ARC!"
  EOT
}
