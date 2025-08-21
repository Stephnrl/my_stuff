#!/bin/bash

#######################################
# Terraform Deployment Script
# Handles bootstrap, team deployments, and orchestrator modules
#######################################

set -e  # Exit on error
set -o pipefail  # Exit on pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
BOOTSTRAP_DIR="${REPO_ROOT}/bootstrap"
TEAMS_DIR="${REPO_ROOT}/teams"
ORCHESTRATOR_DIR="${REPO_ROOT}/orchestrator"

# Default values
DRY_RUN=false
AUTO_APPROVE=false
VERBOSE=false
OPERATION=""

# Pass through GitHub environment variables if set
if [ -n "${GITHUB_TOKEN}" ]; then
    export TF_VAR_github_token="${GITHUB_TOKEN}"
    log_info "GitHub token detected and exported as TF_VAR_github_token"
fi

if [ -n "${GITHUB_OWNER}" ]; then
    export TF_VAR_github_owner="${GITHUB_OWNER}"
    log_info "GitHub owner detected and exported as TF_VAR_github_owner"
fi

#######################################
# Helper Functions
#######################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
    bootstrap       Run bootstrap for a new account
    migrate-state   Migrate local state to remote S3 backend
    team            Run operations on team infrastructure
    module          Run operations on orchestrator modules
    validate-all    Validate all terraform configurations
    plan-all        Run terraform plan for all components

OPTIONS:
    -o, --operation OPERATION    Operation to perform (plan, apply, validate, destroy)
    -a, --account ACCOUNT        Account name for bootstrap
    -t, --team TEAM             Team name for deployment
    -e, --env ENVIRONMENT       Environment (prod, dev, sandbox, etc.)
    -m, --module MODULE         Orchestrator module name (iam, networking, github, etc.)
    -v, --tfvars FILE           Terraform vars file path
    --auto-approve              Auto approve terraform apply/destroy
    --dry-run                   Show what would be executed without running
    --verbose                   Enable verbose output
    -h, --help                  Show this help message

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN                Automatically exported as TF_VAR_github_token if set
    GITHUB_OWNER                Automatically exported as TF_VAR_github_owner if set

EXAMPLES:
    # Bootstrap new account
    $(basename "$0") bootstrap --account account1 --tfvars account1/config.tfvars --operation apply

    # Migrate state after bootstrap
    $(basename "$0") migrate-state --account account1

    # Plan team infrastructure
    $(basename "$0") team --team team1 --env prod --operation plan

    # Apply team infrastructure
    $(basename "$0") team --team team1 --env prod --operation apply

    # Destroy team infrastructure
    $(basename "$0") team --team team1 --env dev --operation destroy --auto-approve

    # Plan orchestrator module
    $(basename "$0") module --module networking --tfvars prod.tfvars --operation plan

    # Apply orchestrator module
    $(basename "$0") module --module networking --tfvars prod.tfvars --operation apply

    # Validate specific team
    $(basename "$0") team --team team1 --env prod --operation validate
EOF
}

check_prerequisites() {
    local missing_tools=()
    
    # Check for required tools
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    command -v git >/dev/null 2>&1 || missing_tools+=("git")
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or expired"
        exit 1
    fi
}

validate_directory() {
    local dir=$1
    local description=$2
    
    if [ ! -d "$dir" ]; then
        log_error "$description directory not found: $dir"
        exit 1
    fi
}

#######################################
# Terraform Operation Functions
#######################################

run_terraform_validate() {
    local dir=$1
    
    log_info "Running terraform validate in $dir..."
    cd "$dir"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would run: terraform init -backend=false"
        log_info "[DRY RUN] Would run: terraform validate"
    else
        terraform init -backend=false -upgrade >/dev/null 2>&1
        if terraform validate; then
            log_success "Validation successful"
            return 0
        else
            log_error "Validation failed"
            return 1
        fi
    fi
}

run_terraform_plan() {
    local dir=$1
    local tfvars_path=$2
    
    log_info "Running terraform plan in $dir..."
    cd "$dir"
    
    # Always validate first
    log_info "Validating configuration first..."
    terraform validate || {
        log_error "Validation failed, skipping plan"
        return 1
    }
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would run: terraform init"
        if [ -n "$tfvars_path" ]; then
            log_info "[DRY RUN] Would run: terraform plan -var-file=$tfvars_path"
        else
            log_info "[DRY RUN] Would run: terraform plan"
        fi
    else
        terraform init -upgrade
        
        if [ -n "$tfvars_path" ]; then
            terraform plan -var-file="$tfvars_path" -out=tfplan
        else
            terraform plan -out=tfplan
        fi
        
        # Clean up plan file after showing it
        rm -f tfplan
    fi
}

run_terraform_apply() {
    local dir=$1
    local tfvars_path=$2
    
    log_info "Running terraform apply in $dir..."
    cd "$dir"
    
    # Always validate first
    log_info "Validating configuration first..."
    terraform validate || {
        log_error "Validation failed, skipping apply"
        return 1
    }
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would run: terraform init"
        if [ -n "$tfvars_path" ]; then
            log_info "[DRY RUN] Would run: terraform plan -var-file=$tfvars_path"
            log_info "[DRY RUN] Would run: terraform apply"
        else
            log_info "[DRY RUN] Would run: terraform plan"
            log_info "[DRY RUN] Would run: terraform apply"
        fi
    else
        terraform init -upgrade
        
        # Plan first
        log_info "Creating execution plan..."
        if [ -n "$tfvars_path" ]; then
            terraform plan -var-file="$tfvars_path" -out=tfplan
        else
            terraform plan -out=tfplan
        fi
        
        # Apply
        if [ "$AUTO_APPROVE" = true ]; then
            log_info "Applying terraform configuration (auto-approve)..."
            terraform apply tfplan
        else
            log_warning "Please review the plan above."
            read -p "Do you want to apply? (yes/no): " -r
            if [[ $REPLY =~ ^[Yy]es$ ]]; then
                terraform apply tfplan
            else
                log_info "Apply cancelled"
                rm -f tfplan
                exit 0
            fi
        fi
        
        rm -f tfplan
    fi
}

run_terraform_destroy() {
    local dir=$1
    local tfvars_path=$2
    
    log_warning "Running terraform destroy in $dir..."
    cd "$dir"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would run: terraform init"
        if [ -n "$tfvars_path" ]; then
            log_info "[DRY RUN] Would run: terraform destroy -var-file=$tfvars_path"
        else
            log_info "[DRY RUN] Would run: terraform destroy"
        fi
    else
        terraform init -upgrade
        
        if [ "$AUTO_APPROVE" = true ]; then
            log_warning "Destroying terraform configuration (auto-approve)..."
            if [ -n "$tfvars_path" ]; then
                terraform destroy -var-file="$tfvars_path" -auto-approve
            else
                terraform destroy -auto-approve
            fi
        else
            log_warning "This will DESTROY all resources. This action cannot be undone!"
            if [ -n "$tfvars_path" ]; then
                terraform destroy -var-file="$tfvars_path"
            else
                terraform destroy
            fi
        fi
    fi
}

#######################################
# Bootstrap Functions
#######################################

run_bootstrap() {
    local account=$1
    local tfvars_file=$2
    local operation=$3
    
    log_info "Running bootstrap for account: $account with operation: $operation"
    
    local bootstrap_account_dir="${BOOTSTRAP_DIR}/${account}"
    validate_directory "$bootstrap_account_dir" "Bootstrap account"
    
    # Check if tfvars file exists (not needed for validate)
    local tfvars_path=""
    if [ "$operation" != "validate" ] && [ -n "$tfvars_file" ]; then
        if [[ "$tfvars_file" = /* ]]; then
            tfvars_path="$tfvars_file"
        else
            tfvars_path="${bootstrap_account_dir}/${tfvars_file}"
        fi
        
        if [ ! -f "$tfvars_path" ]; then
            log_error "Terraform vars file not found: $tfvars_path"
            exit 1
        fi
    fi
    
    # For bootstrap apply, ensure local backend first
    if [ "$operation" = "apply" ] && [ "$DRY_RUN" = false ]; then
        cd "$bootstrap_account_dir"
        cat > backend.tf << 'EOF'
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
        log_info "Configured local backend for bootstrap"
    fi
    
    case $operation in
        validate)
            run_terraform_validate "$bootstrap_account_dir"
            ;;
        plan)
            run_terraform_plan "$bootstrap_account_dir" "$tfvars_path"
            ;;
        apply)
            run_terraform_apply "$bootstrap_account_dir" "$tfvars_path"
            log_success "Bootstrap completed for account: $account"
            log_warning "Remember to run migrate-state to move to remote backend"
            ;;
        destroy)
            run_terraform_destroy "$bootstrap_account_dir" "$tfvars_path"
            ;;
        *)
            log_error "Invalid operation: $operation"
            exit 1
            ;;
    esac
}

migrate_state() {
    local account=$1
    
    log_info "Starting state migration for account: $account"
    
    local bootstrap_account_dir="${BOOTSTRAP_DIR}/${account}"
    validate_directory "$bootstrap_account_dir" "Bootstrap account"
    
    cd "$bootstrap_account_dir"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would retrieve S3 bucket and DynamoDB table from outputs"
        log_info "[DRY RUN] Would update backend.tf with remote configuration"
        log_info "[DRY RUN] Would run: terraform init -migrate-state"
    else
        # Get outputs
        S3_BUCKET=$(terraform output -raw terraform_state_bucket 2>/dev/null || echo "")
        DYNAMODB_TABLE=$(terraform output -raw terraform_state_lock_table 2>/dev/null || echo "")
        REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
        
        if [ -z "$S3_BUCKET" ] || [ -z "$DYNAMODB_TABLE" ]; then
            log_error "Could not retrieve S3 bucket or DynamoDB table from outputs"
            log_error "Make sure bootstrap has been run successfully"
            exit 1
        fi
        
        log_info "S3 Bucket: $S3_BUCKET"
        log_info "DynamoDB Table: $DYNAMODB_TABLE"
        log_info "Region: $REGION"
        
        # Backup current state
        cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
        
        # Create new backend configuration
        cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket         = "${S3_BUCKET}"
    key            = "bootstrap/${account}/terraform.tfstate"
    region         = "${REGION}"
    dynamodb_table = "${DYNAMODB_TABLE}"
    encrypt        = true
  }
}
EOF
        
        log_info "Migrating state to S3 backend..."
        terraform init -migrate-state -force-copy
        
        # Verify migration
        if terraform state list >/dev/null 2>&1; then
            log_success "State migration completed successfully"
            log_info "Local state file backed up with timestamp"
        else
            log_error "State migration verification failed"
            exit 1
        fi
    fi
}

#######################################
# Team Operations
#######################################

team_operation() {
    local team=$1
    local environment=$2
    local operation=$3
    
    log_info "Running $operation for team: $team, environment: $environment"
    
    local team_dir="${TEAMS_DIR}/${team}"
    validate_directory "$team_dir" "Team"
    
    # Check if tfvars file exists (not needed for validate)
    local tfvars_path=""
    if [ "$operation" != "validate" ]; then
        tfvars_path="${team_dir}/${environment}.tfvars"
        if [ ! -f "$tfvars_path" ]; then
            log_error "Terraform vars file not found: $tfvars_path"
            exit 1
        fi
    fi
    
    case $operation in
        validate)
            run_terraform_validate "$team_dir"
            ;;
        plan)
            run_terraform_plan "$team_dir" "$tfvars_path"
            ;;
        apply)
            run_terraform_apply "$team_dir" "$tfvars_path"
            log_success "Apply completed for team: $team, environment: $environment"
            ;;
        destroy)
            run_terraform_destroy "$team_dir" "$tfvars_path"
            log_success "Destroy completed for team: $team, environment: $environment"
            ;;
        *)
            log_error "Invalid operation: $operation"
            exit 1
            ;;
    esac
}

#######################################
# Module Operations
#######################################

module_operation() {
    local module=$1
    local tfvars_file=$2
    local operation=$3
    
    log_info "Running $operation for module: $module"
    
    local module_dir="${ORCHESTRATOR_DIR}/${module}"
    validate_directory "$module_dir" "Module"
    
    # Handle tfvars file path (not needed for validate)
    local tfvars_path=""
    if [ "$operation" != "validate" ] && [ -n "$tfvars_file" ]; then
        if [[ "$tfvars_file" = /* ]]; then
            tfvars_path="$tfvars_file"
        else
            tfvars_path="${module_dir}/${tfvars_file}"
        fi
        
        if [ ! -f "$tfvars_path" ]; then
            log_error "Terraform vars file not found: $tfvars_path"
            exit 1
        fi
    fi
    
    case $operation in
        validate)
            run_terraform_validate "$module_dir"
            ;;
        plan)
            run_terraform_plan "$module_dir" "$tfvars_path"
            ;;
        apply)
            run_terraform_apply "$module_dir" "$tfvars_path"
            log_success "Apply completed for module: $module"
            ;;
        destroy)
            run_terraform_destroy "$module_dir" "$tfvars_path"
            log_success "Destroy completed for module: $module"
            ;;
        *)
            log_error "Invalid operation: $operation"
            exit 1
            ;;
    esac
}

#######################################
# Validation Functions
#######################################

validate_all() {
    log_info "Validating all Terraform configurations..."
    
    local has_errors=false
    
    # Validate bootstrap directories
    if [ -d "$BOOTSTRAP_DIR" ]; then
        log_info "Validating bootstrap configurations..."
        for account_dir in "$BOOTSTRAP_DIR"/*; do
            if [ -d "$account_dir" ]; then
                account=$(basename "$account_dir")
                log_info "  Validating bootstrap/$account..."
                if run_terraform_validate "$account_dir"; then
                    log_success "  ✓ bootstrap/$account is valid"
                else
                    log_error "  ✗ bootstrap/$account validation failed"
                    has_errors=true
                fi
            fi
        done
    fi
    
    # Validate team directories
    if [ -d "$TEAMS_DIR" ]; then
        log_info "Validating team configurations..."
        for team_dir in "$TEAMS_DIR"/*; do
            if [ -d "$team_dir" ]; then
                team=$(basename "$team_dir")
                log_info "  Validating teams/$team..."
                if run_terraform_validate "$team_dir"; then
                    log_success "  ✓ teams/$team is valid"
                else
                    log_error "  ✗ teams/$team validation failed"
                    has_errors=true
                fi
            fi
        done
    fi
    
    # Validate orchestrator modules
    if [ -d "$ORCHESTRATOR_DIR" ]; then
        log_info "Validating orchestrator modules..."
        for module_dir in "$ORCHESTRATOR_DIR"/*; do
            if [ -d "$module_dir" ]; then
                module=$(basename "$module_dir")
                log_info "  Validating orchestrator/$module..."
                if run_terraform_validate "$module_dir"; then
                    log_success "  ✓ orchestrator/$module is valid"
                else
                    log_error "  ✗ orchestrator/$module validation failed"
                    has_errors=true
                fi
            fi
        done
    fi
    
    if [ "$has_errors" = true ]; then
        log_error "Validation failed for one or more configurations"
        exit 1
    else
        log_success "All configurations are valid"
    fi
}

plan_all() {
    log_info "Running terraform plan for all components..."
    
    # Plan teams
    if [ -d "$TEAMS_DIR" ]; then
        for team_dir in "$TEAMS_DIR"/*; do
            if [ -d "$team_dir" ]; then
                team=$(basename "$team_dir")
                for tfvars in "$team_dir"/*.tfvars; do
                    if [ -f "$tfvars" ]; then
                        env=$(basename "$tfvars" .tfvars)
                        log_info "Planning team: $team, environment: $env"
                        cd "$team_dir"
                        terraform init -upgrade >/dev/null 2>&1
                        terraform plan -var-file="$(basename "$tfvars")" -no-color | grep -E "^Plan:|No changes"
                    fi
                done
            fi
        done
    fi
    
    # Plan orchestrator modules
    if [ -d "$ORCHESTRATOR_DIR" ]; then
        for module_dir in "$ORCHESTRATOR_DIR"/*; do
            if [ -d "$module_dir" ]; then
                module=$(basename "$module_dir")
                log_info "Planning module: $module"
                cd "$module_dir"
                terraform init -upgrade >/dev/null 2>&1
                terraform plan -no-color | grep -E "^Plan:|No changes"
            fi
        done
    fi
    
    log_success "Plan complete for all components"
}

#######################################
# Main Script Logic
#######################################

main() {
    # Parse command
    COMMAND=${1:-}
    shift || true
    
    # Parse options
    ACCOUNT=""
    TEAM=""
    ENVIRONMENT=""
    MODULE=""
    TFVARS_FILE=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--operation)
                OPERATION="$2"
                shift 2
                ;;
            -a|--account)
                ACCOUNT="$2"
                shift 2
                ;;
            -t|--team)
                TEAM="$2"
                shift 2
                ;;
            -e|--env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -m|--module)
                MODULE="$2"
                shift 2
                ;;
            -v|--tfvars)
                TFVARS_FILE="$2"
                shift 2
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
                shift
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
    
    # Export GitHub variables if present
    if [ -n "${GITHUB_TOKEN}" ]; then
        export TF_VAR_github_token="${GITHUB_TOKEN}"
        log_info "GitHub token exported as TF_VAR_github_token"
    fi
    
    if [ -n "${GITHUB_OWNER}" ]; then
        export TF_VAR_github_owner="${GITHUB_OWNER}"
        log_info "GitHub owner exported as TF_VAR_github_owner"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Execute command
    case $COMMAND in
        bootstrap)
            if [ -z "$ACCOUNT" ]; then
                log_error "Bootstrap requires --account"
                show_help
                exit 1
            fi
            if [ -z "$OPERATION" ]; then
                log_error "Bootstrap requires --operation (plan, apply, validate, destroy)"
                show_help
                exit 1
            fi
            if [ "$OPERATION" != "validate" ] && [ -z "$TFVARS_FILE" ]; then
                log_error "Bootstrap $OPERATION requires --tfvars"
                show_help
                exit 1
            fi
            run_bootstrap "$ACCOUNT" "$TFVARS_FILE" "$OPERATION"
            ;;
        migrate-state)
            if [ -z "$ACCOUNT" ]; then
                log_error "State migration requires --account"
                show_help
                exit 1
            fi
            migrate_state "$ACCOUNT"
            ;;
        team)
            if [ -z "$TEAM" ] || [ -z "$ENVIRONMENT" ]; then
                log_error "Team operations require --team and --env"
                show_help
                exit 1
            fi
            if [ -z "$OPERATION" ]; then
                log_error "Team operations require --operation (plan, apply, validate, destroy)"
                show_help
                exit 1
            fi
            team_operation "$TEAM" "$ENVIRONMENT" "$OPERATION"
            ;;
        module)
            if [ -z "$MODULE" ]; then
                log_error "Module operations require --module"
                show_help
                exit 1
            fi
            if [ -z "$OPERATION" ]; then
                log_error "Module operations require --operation (plan, apply, validate, destroy)"
                show_help
                exit 1
            fi
            module_operation "$MODULE" "$TFVARS_FILE" "$OPERATION"
            ;;
        validate-all)
            validate_all
            ;;
        plan-all)
            plan_all
            ;;
        *)
            log_error "Invalid command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
