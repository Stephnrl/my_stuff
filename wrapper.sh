#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
OPERATION=""
ENVIRONMENT=""
WORKING_DIR="."
VAR_FILES_DIR="./environments"
STATE_KEY=""
USE_LOCAL_STATE=false
AUTO_APPROVE=false
EXTRA_ARGS=""
PLAN_FILE="tfplan"

# Backend configuration from environment
TF_STATE_BUCKET="${TF_STATE_BUCKET:-}"
TF_STATE_DYNAMODB_TABLE="${TF_STATE_DYNAMODB_TABLE:-}"
TF_STATE_REGION="${TF_STATE_REGION:-us-east-1}"
TF_STATE_ENCRYPT="${TF_STATE_ENCRYPT:-true}"

# Terraform configuration
LOCK_TIMEOUT="${LOCK_TIMEOUT:-300s}"
PARALLELISM="${PARALLELISM:-10}"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_section() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Terraform wrapper script for managing infrastructure deployments.

OPTIONS:
    -o, --operation OPERATION    Terraform operation to perform (required)
                                 Options: init, fmt, validate, plan, apply, destroy, 
                                         full-deploy, bootstrap, migrate-state
    
    -e, --environment ENV        Environment name (e.g., lz-nonprod-01, lz-prod-01)
    
    -w, --working-dir DIR        Working directory for Terraform files (default: .)
    
    -v, --var-dir DIR           Directory containing tfvars files (default: ./environments)
    
    -k, --state-key KEY         Override state key for backend (default: <environment>/terraform.tfstate)
    
    -l, --local-state           Use local state instead of remote backend
    
    -a, --auto-approve          Auto-approve for apply/destroy (use with caution)
    
    -x, --extra-args ARGS       Extra arguments to pass to terraform commands
    
    -h, --help                  Show this help message

ENVIRONMENT VARIABLES:
    TF_STATE_BUCKET            S3 bucket for state storage
    TF_STATE_DYNAMODB_TABLE    DynamoDB table for state locking
    TF_STATE_REGION           AWS region for state backend (default: us-east-1)
    TF_STATE_ENCRYPT          Enable state encryption (default: true)
    LOCK_TIMEOUT              Lock timeout duration (default: 300s)
    PARALLELISM               Parallelism for terraform operations (default: 10)

EXAMPLES:
    # Initialize with remote backend
    $0 -o init -e lz-nonprod-01

    # Format check
    $0 -o fmt -w ./infrastructure

    # Plan changes for non-prod
    $0 -o plan -e lz-nonprod-01

    # Apply changes with auto-approval (for CI/CD)
    $0 -o apply -e lz-prod-01 -a

    # Use local state for bootstrap
    $0 -o bootstrap -l

    # Custom state key
    $0 -o plan -e lz-nonprod-01 -k "custom/path/terraform.tfstate"

    # Full deployment pipeline
    $0 -o full-deploy -e lz-nonprod-01

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--operation)
                OPERATION="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -w|--working-dir)
                WORKING_DIR="$2"
                shift 2
                ;;
            -v|--var-dir)
                VAR_FILES_DIR="$2"
                shift 2
                ;;
            -k|--state-key)
                STATE_KEY="$2"
                shift 2
                ;;
            -l|--local-state)
                USE_LOCAL_STATE=true
                shift
                ;;
            -a|--auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            -x|--extra-args)
                EXTRA_ARGS="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -z "$OPERATION" ]]; then
        log_error "Operation is required"
        show_help
        exit 1
    fi
}

# Check if terraform is installed
check_terraform() {
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi
    log_info "Terraform version: $(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1)"
}

# Build backend configuration
build_backend_config() {
    local backend_args=""
    
    if [[ "$USE_LOCAL_STATE" == "true" ]]; then
        log_info "Using local state backend"
        return
    fi
    
    # Check if backend environment variables are set
    if [[ -z "$TF_STATE_BUCKET" ]]; then
        log_warn "TF_STATE_BUCKET not set, using local backend"
        USE_LOCAL_STATE=true
        return
    fi
    
    # Build backend configuration arguments
    backend_args="-backend-config=bucket=$TF_STATE_BUCKET"
    backend_args="$backend_args -backend-config=region=$TF_STATE_REGION"
    backend_args="$backend_args -backend-config=encrypt=$TF_STATE_ENCRYPT"
    
    # Add DynamoDB table if specified
    if [[ -n "$TF_STATE_DYNAMODB_TABLE" ]]; then
        backend_args="$backend_args -backend-config=dynamodb_table=$TF_STATE_DYNAMODB_TABLE"
    fi
    
    # Determine state key
    local state_key="$STATE_KEY"
    if [[ -z "$state_key" ]] && [[ -n "$ENVIRONMENT" ]]; then
        state_key="${ENVIRONMENT}/terraform.tfstate"
    elif [[ -z "$state_key" ]]; then
        state_key="terraform.tfstate"
    fi
    backend_args="$backend_args -backend-config=key=$state_key"
    
    log_info "Backend configuration:"
    log_info "  Bucket: $TF_STATE_BUCKET"
    log_info "  State Key: $state_key"
    log_info "  Region: $TF_STATE_REGION"
    if [[ -n "$TF_STATE_DYNAMODB_TABLE" ]]; then
        log_info "  DynamoDB Table: $TF_STATE_DYNAMODB_TABLE"
    fi
    
    echo "$backend_args"
}

# Build var-file arguments for terraform
build_var_args() {
    local var_args=""
    
    if [[ -n "$ENVIRONMENT" ]]; then
        # Check for environment-specific tfvars
        local env_file="${VAR_FILES_DIR}/${ENVIRONMENT}.tfvars"
        if [[ -f "$env_file" ]]; then
            var_args="$var_args -var-file=$env_file"
            log_info "Using environment file: $env_file"
        else
            log_warn "Environment file not found: $env_file (continuing without it)"
        fi
        
        # Check for team-specific tfvars (if pattern matches)
        # This assumes team files follow a pattern, adjust as needed
        for team_file in "${VAR_FILES_DIR}"/*.tfvars; do
            if [[ -f "$team_file" ]] && [[ "$(basename "$team_file")" != "${ENVIRONMENT}.tfvars" ]]; then
                # Skip environment files, only add team/common files
                case "$(basename "$team_file")" in
                    common.tfvars|global.tfvars|devsecops.tfvars|platform.tfvars|data.tfvars)
                        var_args="$var_args -var-file=$team_file"
                        log_info "Using additional var file: $team_file"
                        ;;
                esac
            fi
        done
    fi
    
    echo "$var_args"
}

# Initialize terraform
terraform_init() {
    log_section "Terraform Init"
    
    cd "$WORKING_DIR"
    
    if [[ "$USE_LOCAL_STATE" == "true" ]]; then
        log_info "Initializing with local backend"
        terraform init $EXTRA_ARGS
    else
        local backend_config=$(build_backend_config)
        if [[ -n "$backend_config" ]]; then
            log_info "Initializing with remote backend"
            terraform init $backend_config $EXTRA_ARGS
        else
            log_info "Initializing with default backend configuration"
            terraform init $EXTRA_ARGS
        fi
    fi
}

# Format command
cmd_fmt() {
    log_section "Terraform Format"
    
    cd "$WORKING_DIR"
    
    terraform fmt -recursive -diff
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "All files are properly formatted"
    elif [[ $exit_code -eq 3 ]]; then
        log_warn "Some files were reformatted"
        if [[ "${CI:-false}" == "true" ]]; then
            log_error "Format check failed in CI. Run 'terraform fmt' locally and commit changes."
            exit 1
        fi
    else
        log_error "Format check failed"
        exit $exit_code
    fi
}

# Validate command
cmd_validate() {
    log_section "Terraform Validate"
    
    terraform_init
    terraform validate
    log_info "Configuration is valid"
}

# Plan command
cmd_plan() {
    log_section "Terraform Plan"
    
    terraform_init
    
    local var_args=$(build_var_args)
    
    log_info "Running terraform plan..."
    terraform plan \
        $var_args \
        -lock-timeout=$LOCK_TIMEOUT \
        -parallelism=$PARALLELISM \
        -out=$PLAN_FILE \
        $EXTRA_ARGS
    
    log_info "Plan saved to: $PLAN_FILE"
    
    # Show plan summary
    echo -e "\n${GREEN}Plan Summary:${NC}"
    terraform show -no-color $PLAN_FILE 2>/dev/null | tail -20
}

# Apply command
cmd_apply() {
    log_section "Terraform Apply"
    
    terraform_init
    
    local var_args=$(build_var_args)
    
    if [[ -f "$PLAN_FILE" ]] && [[ -z "$var_args" ]]; then
        log_info "Applying saved plan: $PLAN_FILE"
        terraform apply \
            -lock-timeout=$LOCK_TIMEOUT \
            -parallelism=$PARALLELISM \
            "$PLAN_FILE"
    else
        log_info "Running terraform apply..."
        if [[ "$AUTO_APPROVE" == "true" ]]; then
            terraform apply \
                $var_args \
                -lock-timeout=$LOCK_TIMEOUT \
                -parallelism=$PARALLELISM \
                -auto-approve \
                $EXTRA_ARGS
        else
            terraform apply \
                $var_args \
                -lock-timeout=$LOCK_TIMEOUT \
                -parallelism=$PARALLELISM \
                $EXTRA_ARGS
        fi
    fi
    
    log_info "Apply complete!"
}

# Destroy command
cmd_destroy() {
    log_section "Terraform Destroy"
    
    if [[ "$AUTO_APPROVE" != "true" ]]; then
        log_warn "WARNING: This will destroy all resources!"
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Destroy cancelled"
            exit 0
        fi
    fi
    
    terraform_init
    
    local var_args=$(build_var_args)
    
    log_info "Running terraform destroy..."
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        terraform destroy \
            $var_args \
            -lock-timeout=$LOCK_TIMEOUT \
            -parallelism=$PARALLELISM \
            -auto-approve \
            $EXTRA_ARGS
    else
        terraform destroy \
            $var_args \
            -lock-timeout=$LOCK_TIMEOUT \
            -parallelism=$PARALLELISM \
            $EXTRA_ARGS
    fi
    
    log_info "Destroy complete!"
}

# Bootstrap command (uses local state)
cmd_bootstrap() {
    log_section "Bootstrap Phase"
    
    # Force local state for bootstrap
    USE_LOCAL_STATE=true
    
    log_info "Running bootstrap with local state..."
    
    cd "$WORKING_DIR"
    
    # Initialize with local backend
    terraform init $EXTRA_ARGS
    
    # Apply bootstrap configuration
    log_info "Creating bootstrap infrastructure..."
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        terraform apply -auto-approve $EXTRA_ARGS
    else
        terraform apply $EXTRA_ARGS
    fi
    
    # Output the created resources
    log_info "Bootstrap complete! Created resources:"
    terraform output -json 2>/dev/null | jq -r 'to_entries[] | "\(.key): \(.value.value)"' || true
    
    log_info "Next step: Configure backend environment variables and run 'migrate-state'"
}

# Migrate state from local to remote
cmd_migrate_state() {
    log_section "State Migration"
    
    cd "$WORKING_DIR"
    
    # Check if local state exists
    if [[ ! -f "terraform.tfstate" ]]; then
        log_error "Local state file not found: terraform.tfstate"
        log_error "Run bootstrap first to create initial infrastructure"
        exit 1
    fi
    
    # Check backend configuration
    if [[ -z "$TF_STATE_BUCKET" ]]; then
        log_error "TF_STATE_BUCKET environment variable not set"
        log_error "Please set the backend configuration environment variables first"
        exit 1
    fi
    
    # Get backend configuration
    local backend_config=$(build_backend_config)
    
    # Initialize with backend and migrate
    log_info "Migrating state to remote backend..."
    terraform init $backend_config -migrate-state -force-copy
    
    log_info "State migration complete!"
    log_info "Local state has been migrated to:"
    log_info "  Bucket: $TF_STATE_BUCKET"
    log_info "  Key: ${STATE_KEY:-${ENVIRONMENT}/terraform.tfstate}"
}

# Full deployment pipeline
cmd_full_deploy() {
    log_section "Full Deployment Pipeline"
    
    # Run format check
    cmd_fmt
    
    # Validate configuration
    cmd_validate
    
    # Create plan
    cmd_plan
    
    # Apply if auto-approve is set
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        cmd_apply
    else
        log_info "Plan complete. Review the plan and run 'apply' to deploy changes."
    fi
}

# Main execution
main() {
    parse_args "$@"
    check_terraform
    
    # Validate working directory
    if [[ ! -d "$WORKING_DIR" ]]; then
        log_error "Working directory does not exist: $WORKING_DIR"
        exit 1
    fi
    
    # Execute the requested operation
    case "$OPERATION" in
        init)
            terraform_init
            ;;
        fmt)
            cmd_fmt
            ;;
        validate)
            cmd_validate
            ;;
        plan)
            cmd_plan
            ;;
        apply)
            cmd_apply
            ;;
        destroy)
            cmd_destroy
            ;;
        bootstrap)
            cmd_bootstrap
            ;;
        migrate-state)
            cmd_migrate_state
            ;;
        full-deploy)
            cmd_full_deploy
            ;;
        *)
            log_error "Unknown operation: $OPERATION"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
