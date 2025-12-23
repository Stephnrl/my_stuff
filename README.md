# ARC Deployment Terraform Module

This Terraform module deploys GitHub Actions Runner Controller (ARC) to a Kubernetes cluster.

## Features

- Deploys ARC Controller and Runner Scale Sets
- Supports JFrog Artifactory for private images
- GitHub App or PAT authentication
- Configurable scaling (min/max runners)
- Docker-in-Docker (DinD) support
- Environment-aware configuration

## Prerequisites

1. **Existing AKS Cluster** - The module assumes you have a running AKS cluster
2. **GitHub App** - Recommended for authentication (see setup below)
3. **Terraform >= 1.5.0**
4. **Helm >= 3.8.0** (installed on the machine running Terraform)

## GitHub App Setup

1. Go to your GitHub Organization → Settings → Developer settings → GitHub Apps
2. Click "New GitHub App"
3. Configure:
   - **Name**: `ARC Runner Controller`
   - **Homepage URL**: Your org URL
   - **Webhook**: Uncheck "Active"
   - **Permissions**:
     - Repository: Actions (Read), Metadata (Read)
     - Organization: Self-hosted runners (Read & Write)
   - **Where can this GitHub App be installed?**: Only on this account
4. After creation:
   - Note the **App ID**
   - Generate and download the **Private Key**
   - Install the app on your organization
   - Note the **Installation ID** from the URL

## Usage

```hcl
module "arc" {
  source = "path/to/modules/arc-deployment"

  # Namespaces
  controller_namespace = "arc-systems"
  runners_namespace    = "arc-runners"

  # GitHub Configuration
  github_config = {
    url          = "https://github.com/your-org"
    runner_group = ""  # Optional: specific runner group
  }

  github_auth = {
    secret_name         = "arc-github-secret"
    use_app             = true
    app_id              = "123456"
    app_installation_id = "654321"
    app_private_key     = file("path/to/private-key.pem")
    pat_token           = ""
  }

  # Runner Configuration
  runner_scale_set_name = "arc-runners"
  runner_scaling = {
    min_runners = 0
    max_runners = 10
  }

  # Container mode for Docker support
  container_mode = "dind"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `create_namespaces` | Create namespaces | `bool` | `true` | no |
| `controller_namespace` | Controller namespace | `string` | `"arc-systems"` | no |
| `runners_namespace` | Runners namespace | `string` | `"arc-runners"` | no |
| `chart_version` | ARC Helm chart version | `string` | `"0.10.0"` | no |
| `deploy_controller` | Deploy the controller | `bool` | `true` | no |
| `github_config` | GitHub configuration | `object` | n/a | yes |
| `github_auth` | GitHub authentication | `object` | n/a | yes |
| `runner_scale_set_name` | Runner name (runs-on) | `string` | `"arc-runner-set"` | no |
| `runner_scaling` | Min/max runners | `object` | `{min:0, max:10}` | no |
| `container_mode` | none, dind, kubernetes | `string` | `"dind"` | no |
| `jfrog_config` | JFrog configuration | `object` | disabled | no |

## Outputs

| Name | Description |
|------|-------------|
| `runner_scale_set_name` | Use in workflow `runs-on` |
| `controller_namespace` | Controller namespace |
| `runners_namespace` | Runners namespace |
| `workflow_runs_on_example` | Example workflow YAML |

## Using with JFrog

If you're using JFrog Artifactory:

1. Mirror the required images to JFrog:
   ```bash
   # Pull from GitHub
   docker pull ghcr.io/actions/gha-runner-scale-set-controller:0.10.0
   docker pull ghcr.io/actions/actions-runner:latest
   docker pull docker:dind

   # Tag for JFrog
   docker tag ghcr.io/actions/gha-runner-scale-set-controller:0.10.0 \
     your-company.jfrog.io/docker-local/arc/gha-runner-scale-set-controller:0.10.0
   
   docker tag ghcr.io/actions/actions-runner:latest \
     your-company.jfrog.io/docker-local/arc/actions-runner:latest
   
   docker tag docker:dind \
     your-company.jfrog.io/docker-local/docker:dind

   # Push to JFrog
   docker push your-company.jfrog.io/docker-local/arc/gha-runner-scale-set-controller:0.10.0
   docker push your-company.jfrog.io/docker-local/arc/actions-runner:latest
   docker push your-company.jfrog.io/docker-local/docker:dind
   ```

2. Configure the module:
   ```hcl
   jfrog_config = {
     enabled     = true
     server      = "your-company.jfrog.io"
     username    = var.jfrog_username
     password    = var.jfrog_password
     secret_name = "jfrog-pull-secret"
   }

   runner_image = {
     repository  = "your-company.jfrog.io/docker-local/arc/actions-runner"
     tag         = "latest"
     pull_policy = "IfNotPresent"
   }
   ```

## Deployment Steps

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Create terraform.tfvars**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Plan and Apply**:
   ```bash
   terraform plan
   terraform apply
   ```

4. **Verify deployment**:
   ```bash
   # Check controller
   kubectl get pods -n arc-systems
   
   # Check listener
   kubectl get pods -n arc-runners
   ```

5. **Test with a workflow**:
   ```yaml
   name: Test ARC
   on: workflow_dispatch
   jobs:
     test:
       runs-on: arc-runner-set  # Use your runner_scale_set_name
       steps:
         - run: echo "Hello from ARC!"
   ```

## Troubleshooting

### Controller not starting
```bash
kubectl logs -n arc-systems -l app.kubernetes.io/name=gha-runner-scale-set-controller
```

### Runners not picking up jobs
```bash
kubectl logs -n arc-runners -l app.kubernetes.io/component=listener
```

### Image pull errors
```bash
kubectl get events -n arc-runners --sort-by='.lastTimestamp'
kubectl describe pod <pod-name> -n arc-runners
```
