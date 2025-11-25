#!/bin/bash
# =============================================================================
# Golden AMI Build Script
# =============================================================================
# Wrapper script for building Golden AMIs with Packer
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="${SCRIPT_DIR}/../packer"
LOG_DIR="${SCRIPT_DIR}/../logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create logs directory
mkdir -p "${LOG_DIR}"

# Timestamp for logging
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/build_${TIMESTAMP}.log"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] COMMAND

Commands:
    validate    Validate Packer configuration
    inspect     Show Packer build details
    build       Build the Golden AMI
    clean       Remove local build artifacts

Options:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output
    -d, --debug     Enable debug mode (PACKER_LOG=1)
    --var KEY=VAL   Pass variable to Packer

Examples:
    $(basename "$0") validate
    $(basename "$0") build
    $(basename "$0") build --var ami_prefix=my-golden-ami
    $(basename "$0") build -v --var ami_version=2.0.0

EOF
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Packer
    if ! command -v packer &> /dev/null; then
        log_error "Packer is not installed. Run: ./scripts/install-packer.sh"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check Ansible (for Packer provisioner)
    if ! command -v ansible &> /dev/null; then
        log_error "Ansible is not installed. Activate your environment: source ~/activate-ansible.sh"
        exit 1
    fi
    
    log_info "All prerequisites met!"
}

do_validate() {
    log_info "Validating Packer configuration..."
    cd "${PACKER_DIR}"
    
    packer init .
    packer validate ${PACKER_VARS} .
    
    log_info "Configuration is valid!"
}

do_inspect() {
    log_info "Inspecting Packer configuration..."
    cd "${PACKER_DIR}"
    
    packer inspect golden-ami.pkr.hcl
}

do_build() {
    log_info "Starting Golden AMI build..."
    log_info "Log file: ${LOG_FILE}"
    
    cd "${PACKER_DIR}"
    
    # Initialize Packer (download plugins)
    packer init .
    
    # Build command
    BUILD_CMD="packer build -color=true -timestamp-ui ${PACKER_VARS} ."
    
    if [[ "${DEBUG}" == "true" ]]; then
        export PACKER_LOG=1
        export PACKER_LOG_PATH="${LOG_FILE}"
    fi
    
    log_info "Running: ${BUILD_CMD}"
    echo "============================================" | tee -a "${LOG_FILE}"
    echo "Build started at: $(date)" | tee -a "${LOG_FILE}"
    echo "============================================" | tee -a "${LOG_FILE}"
    
    if ${BUILD_CMD} 2>&1 | tee -a "${LOG_FILE}"; then
        log_info "Build completed successfully!"
        log_info "Check ${PACKER_DIR}/manifest.json for AMI details"
    else
        log_error "Build failed! Check log: ${LOG_FILE}"
        exit 1
    fi
}

do_clean() {
    log_info "Cleaning up build artifacts..."
    
    cd "${PACKER_DIR}"
    
    rm -f manifest.json
    rm -f crash.log
    rm -rf .packer.d/
    
    log_info "Cleanup complete!"
}

# Parse arguments
VERBOSE=false
DEBUG=false
PACKER_VARS=""
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        --var)
            PACKER_VARS="${PACKER_VARS} -var $2"
            shift 2
            ;;
        validate|inspect|build|clean)
            COMMAND=$1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main
if [[ -z "${COMMAND}" ]]; then
    usage
    exit 1
fi

check_prerequisites

case "${COMMAND}" in
    validate)
        do_validate
        ;;
    inspect)
        do_inspect
        ;;
    build)
        do_build
        ;;
    clean)
        do_clean
        ;;
esac
