#!/bin/bash
# deploy.sh - Main deployment script with enhanced logging and error handling

set -e

# Configuration
ANSIBLE_DIR="$(dirname $0)"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.yml"
PLAYBOOK_FILE="$ANSIBLE_DIR/playbooks/deploy-monitoring.yml"

# Logging configuration
LOG_DIR="$ANSIBLE_DIR/logs"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Setup logging
setup_logging() {
    mkdir -p "$LOG_DIR"
    
    # Create log file
    touch "$LOG_FILE"
    
    # Setup log rotation (keep last 10 logs)
    find "$LOG_DIR" -name "deployment-*.log" -type f -mtime +7 -delete 2>/dev/null || true
    
    echo "=== Deployment Log Started at $(date) ===" >> "$LOG_FILE"
    echo "Command: $0 $*" >> "$LOG_FILE"
    echo "User: $(whoami)" >> "$LOG_FILE"
    echo "Working Directory: $(pwd)" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
}

# Logging functions
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_status() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message"
    log_to_file "INFO: $message"
}

print_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} $message"
    log_to_file "WARN: $message"
}

print_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message"
    log_to_file "ERROR: $message"
}

print_debug() {
    local message="$1"
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $message"
    fi
    log_to_file "DEBUG: $message"
}

# Cleanup function for failures
cleanup_on_failure() {
    local exit_code=$?
    print_error "Deployment failed with exit code $exit_code"
    log_to_file "FATAL: Deployment failed with exit code $exit_code"
    
    print_warning "Check log file for details: $LOG_FILE"
    
    # Optionally run cleanup playbook
    if [[ -f "$ANSIBLE_DIR/playbooks/cleanup.yml" ]]; then
        print_warning "Running cleanup playbook..."
        ansible-playbook -i "$INVENTORY_FILE" "$ANSIBLE_DIR/playbooks/cleanup.yml" \
            --become 2>&1 | tee -a "$LOG_FILE" || true
    fi
    
    exit $exit_code
}

# Set trap for cleanup
trap cleanup_on_failure ERR

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v ansible-playbook &> /dev/null; then
        missing_tools+=("ansible")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if ! command -v ansible-inventory &> /dev/null; then
        missing_tools+=("ansible (inventory command)")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install missing tools before continuing."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        print_warning "Docker not found locally. Make sure it's installed on target hosts."
    fi
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        print_error "Inventory file not found: $INVENTORY_FILE"
        exit 1
    fi
    
    if [[ ! -f "$PLAYBOOK_FILE" ]]; then
        print_error "Playbook file not found: $PLAYBOOK_FILE"
        exit 1
    fi
    
    # Validate inventory syntax
    if ! ansible-inventory -i "$INVENTORY_FILE" --list &>/dev/null; then
        print_error "Invalid inventory file syntax: $INVENTORY_FILE"
        exit 1
    fi
    
    print_status "Prerequisites check completed."
}

# Test connectivity to all hosts
test_connectivity() {
    print_status "Testing connectivity to all hosts..."
    
    if ansible all -i "$INVENTORY_FILE" -m ping 2>&1 | tee -a "$LOG_FILE"; then
        print_status "All hosts are reachable."
    else
        print_error "Some hosts are not reachable. Please check your inventory and SSH configuration."
        print_error "Check log file for detailed connection errors: $LOG_FILE"
        exit 1
    fi
}

# Validate playbook syntax
validate_playbook() {
    print_status "Validating playbook syntax..."
    
    if ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" --syntax-check 2>&1 | tee -a "$LOG_FILE"; then
        print_status "Playbook syntax is valid."
    else
        print_error "Playbook syntax validation failed."
        exit 1
    fi
}

# Deploy monitoring stack
deploy_monitoring() {
    print_status "Deploying monitoring stack..."
    
    local ansible_opts=("--become")
    
    if [[ "$VERBOSE" == "true" ]]; then
        ansible_opts+=("-v")
    fi
    
    # Run the actual deployment
    if ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" "${ansible_opts[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        print_status "Deployment completed successfully!"
        log_to_file "SUCCESS: Deployment completed successfully"
    else
        print_error "Deployment failed!"
        log_to_file "FATAL: Deployment failed"
        exit 1
    fi
}

# Run dry-run
run_dry_run() {
    print_status "Running dry-run - showing what would be deployed..."
    print_warning "This is a simulation - no actual changes will be made."
    
    local ansible_opts=("--become" "--check" "--diff")
    
    if [[ "$VERBOSE" == "true" ]]; then
        ansible_opts+=("-v")
    fi
    
    if ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" "${ansible_opts[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        print_status "Dry-run completed successfully!"
        print_status "Review the output above to see what would be changed."
    else
        print_error "Dry-run failed - there may be issues with your playbook."
        exit 1
    fi
}

# Update existing deployment
update_deployment() {
    print_status "Updating monitoring stack..."
    
    local ansible_opts=("--become" "--tags" "update")
    
    if [[ "$VERBOSE" == "true" ]]; then
        ansible_opts+=("-v")
    fi
    
    if ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" "${ansible_opts[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        print_status "Update completed successfully!"
    else
        print_error "Update failed!"
        exit 1
    fi
}

# Display access information
show_access_info() {
    print_status "Monitoring stack access information:"
    echo ""
    
    # Check if inventory commands work
    if ! ansible-inventory -i "$INVENTORY_FILE" --list &>/dev/null; then
        print_error "Could not read inventory file. Check inventory syntax."
        return 1
    fi
    
    # Get master node IP with error handling
    local master_ip
    if master_ip=$(ansible-inventory -i "$INVENTORY_FILE" --host master-node 2>/dev/null | jq -r '.ansible_host' 2>/dev/null); then
        if [[ "$master_ip" == "null" || -z "$master_ip" ]]; then
            print_warning "Master node IP not found in inventory. Using hostname instead."
            master_ip="master-node"
        fi
    else
        print_warning "Could not retrieve master node IP. Using hostname instead."
        master_ip="master-node"
    fi
    
    echo -e "🌐 ${GREEN}Web Interfaces:${NC}"
    echo -e "   Grafana Dashboard: http://$master_ip:3030"
    echo -e "   Username: admin"
    echo -e "   Password: admin123"
    echo ""
    echo -e "   Prometheus: http://$master_ip:9090"
    # echo -e "   Alertmanager: http://$master_ip:9093"
    echo ""
    
    print_status "📊 Individual exporter endpoints:"
    
    # List GPU nodes with better error handling
    if gpu_hosts=$(ansible-inventory -i "$INVENTORY_FILE" --list 2>/dev/null | jq -r '.gpu_nodes.hosts[]?' 2>/dev/null); then
        if [[ -n "$gpu_hosts" ]]; then
            while IFS= read -r host; do
                if [[ -n "$host" ]]; then
                    local host_ip
                    if host_ip=$(ansible-inventory -i "$INVENTORY_FILE" --host "$host" 2>/dev/null | jq -r '.ansible_host' 2>/dev/null); then
                        if [[ "$host_ip" == "null" || -z "$host_ip" ]]; then
                            host_ip="$host"
                        fi
                        echo -e "  🖥️  GPU Node ($host):"
                        echo -e "     GPU Exporter: http://$host_ip:9200/metrics"
                        echo -e "     DCGM Exporter: http://$host_ip:9400/metrics"
                        echo -e "     Node Exporter: http://$host_ip:9100/metrics"
                        echo ""
                    fi
                fi
            done <<< "$gpu_hosts"
        else
            print_warning "No GPU nodes found in inventory."
        fi
    else
        print_warning "Could not parse GPU nodes from inventory."
    fi
    
    echo -e "📁 ${GREEN}Log file location:${NC} $LOG_FILE"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                COMMAND="$1"
                shift
                ;;
        esac
    done
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  check     - Check prerequisites and connectivity"
    echo "  deploy    - Full deployment (default)"
    echo "  dry-run   - Show what would be deployed without making changes"
    echo "  update    - Update existing deployment"
    echo "  info      - Show access information"
    echo "  validate  - Validate playbook syntax only"
    echo ""
    echo "Options:"
    echo "  -v, --verbose  - Enable verbose output"
    echo "  -h, --help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run full deployment"
    echo "  $0 -v deploy         # Run deployment with verbose output"
    echo "  $0 dry-run           # Preview what would be deployed"
    echo "  $0 check             # Only check prerequisites"
    echo "  $0 info              # Show access URLs"
    echo ""
    echo "Log files are stored in: $LOG_DIR/"
}

# Main function
main() {
    # Setup logging first
    setup_logging
    
    echo "=== 🚀 Monitoring Stack Deployment ==="
    echo ""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Default command
    COMMAND="${COMMAND:-deploy}"
    
    print_debug "Starting deployment with command: $COMMAND"
    print_debug "Log file: $LOG_FILE"
    print_debug "Verbose mode: $VERBOSE"
    
    case "$COMMAND" in
        "check")
            check_prerequisites
            test_connectivity
            print_status "✅ All checks passed!"
            ;;
        "validate")
            check_prerequisites
            validate_playbook
            print_status "✅ Playbook validation passed!"
            ;;
        "deploy")
            check_prerequisites
            test_connectivity
            validate_playbook
            deploy_monitoring
            echo ""
            show_access_info
            print_status "✅ Deployment completed successfully!"
            ;;
        "dry-run")
            check_prerequisites
            test_connectivity
            validate_playbook
            run_dry_run
            print_status "✅ Dry-run completed!"
            ;;
        "update")
            check_prerequisites
            test_connectivity
            validate_playbook
            update_deployment
            print_status "✅ Update completed!"
            ;;
        "info")
            show_access_info
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            echo ""
            show_usage
            exit 1
            ;;
    esac
    
    log_to_file "SUCCESS: Command '$COMMAND' completed successfully"
    echo ""
    print_status "📋 Full execution log saved to: $LOG_FILE"
}

# Run main function with all arguments
main "$@"