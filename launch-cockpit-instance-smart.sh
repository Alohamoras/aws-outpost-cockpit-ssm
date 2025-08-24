#!/bin/bash

# AWS Outpost Cockpit Instance Launch Script - Smart Idempotent Version
# Automatically detects state and resumes from last successful phase

set -e

# Load environment variables
if [[ -f .env ]]; then
    source .env
fi

# Configuration
OUTPOST_ID="${OUTPOST_ID:-op-0c81637caaa70bcb8}"
SUBNET_ID="${SUBNET_ID:-subnet-0ccfe76ef0f0071f6}"
SECURITY_GROUP_ID="${SECURITY_GROUP_ID:-sg-03e548d8a756262fb}"
KEY_NAME="${KEY_NAME:-ryanfill}"
INSTANCE_TYPE="${INSTANCE_TYPE:-c6id.metal}"
REGION="${REGION:-us-east-1}"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN}"
KEY_FILE="${KEY_NAME}.pem"

# Deployment phases in order
PHASES=(
    "bootstrap:Minimal Bootstrap"
    "system-updates:System Updates"
    "cockpit-core:Core Cockpit Installation"
    "cockpit-extensions:Cockpit Extensions"
    "cockpit-thirdparty:Third-party Extensions"  
    "cockpit-config:Final Configuration"
)

# SSM document mapping function
get_ssm_doc() {
    case "$1" in
        "system-updates") echo "outpost-system-updates" ;;
        "cockpit-core") echo "outpost-cockpit-core" ;;
        "cockpit-extensions") echo "outpost-cockpit-extensions" ;;
        "cockpit-thirdparty") echo "outpost-cockpit-thirdparty" ;;
        "cockpit-config") echo "outpost-cockpit-config" ;;
        *) echo "" ;;
    esac
}

# Colors and logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $1"; }
warning() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $1"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $1"; }

# Usage information
show_usage() {
    cat << 'EOF'
AWS Outpost Cockpit Deployment - Smart Idempotent Launcher

USAGE:
    ./launch-cockpit-instance-smart.sh [OPTIONS]

OPTIONS:
    --status                Show current deployment status
    --resume               Resume from last failure point
    --phase <name>         Run specific phase only
    --force-new            Start completely fresh (terminates existing)
    --list-phases          Show all available phases
    --help                 Show this help

PHASES:
    bootstrap              Minimal bootstrap (network + SSM)
    system-updates         System package updates
    cockpit-core          Core Cockpit installation
    cockpit-extensions    Virtualization, containers, monitoring
    cockpit-thirdparty    45Drives extensions
    cockpit-config        Final configuration

EXAMPLES:
    # Smart detection and resume (default)
    ./launch-cockpit-instance-smart.sh
    
    # Check current status
    ./launch-cockpit-instance-smart.sh --status
    
    # Resume from failure
    ./launch-cockpit-instance-smart.sh --resume
    
    # Run specific phase only
    ./launch-cockpit-instance-smart.sh --phase cockpit-core
    
    # Start completely fresh
    ./launch-cockpit-instance-smart.sh --force-new

EOF
}

# Parse command line arguments
FORCE_NEW=false
RESUME=false
STATUS_ONLY=false
SPECIFIC_PHASE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --status)
            STATUS_ONLY=true
            shift
            ;;
        --resume)
            RESUME=true
            shift
            ;;
        --phase)
            SPECIFIC_PHASE="$2"
            shift 2
            ;;
        --force-new)
            FORCE_NEW=true
            shift
            ;;
        --list-phases)
            echo "Available phases:"
            for phase_info in "${PHASES[@]}"; do
                phase_name="${phase_info%%:*}"
                phase_desc="${phase_info##*:}"
                echo "  $phase_name - $phase_desc"
            done
            exit 0
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Find existing instance
find_existing_instance() {
    if [[ -f .last-instance-id ]]; then
        INSTANCE_ID=$(grep "Instance ID:" .last-instance-id | cut -d' ' -f3)
        if [[ -n "$INSTANCE_ID" ]]; then
            # Check if instance still exists and is running
            local state=$(aws ec2 describe-instances \
                --region "$REGION" \
                --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].State.Name' \
                --output text 2>/dev/null || echo "not-found")
            
            if [[ "$state" == "running" ]]; then
                PUBLIC_IP=$(aws ec2 describe-instances \
                    --region "$REGION" \
                    --instance-ids "$INSTANCE_ID" \
                    --query 'Reservations[0].Instances[0].PublicIpAddress' \
                    --output text 2>/dev/null)
                return 0
            elif [[ "$state" != "not-found" ]]; then
                warning "Existing instance $INSTANCE_ID is in state: $state"
            fi
        fi
    fi
    INSTANCE_ID=""
    PUBLIC_IP=""
    return 1
}

# Check phase status on instance
check_phase_status() {
    local phase="$1"
    if [[ -z "$INSTANCE_ID" ]] || [[ -z "$PUBLIC_IP" ]]; then
        echo "not-started"
        return 1
    fi
    
    case "$phase" in
        "bootstrap")
            # Check if minimal bootstrap completed
            if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
                "test -f /tmp/bootstrap-complete" 2>/dev/null; then
                echo "completed"
            else
                echo "not-started"
            fi
            ;;
        "system-updates")
            if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
                "test -f /tmp/phase-system-updates-complete" 2>/dev/null; then
                echo "completed"
            else
                echo "not-started"
            fi
            ;;
        "cockpit-core")
            if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
                "test -f /tmp/phase-cockpit-core-complete" 2>/dev/null; then
                echo "completed"
            else
                echo "not-started"
            fi
            ;;
        "cockpit-extensions")
            if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
                "test -f /tmp/phase-cockpit-extensions-complete" 2>/dev/null; then
                echo "completed"
            else
                echo "not-started"
            fi
            ;;
        "cockpit-thirdparty")
            if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
                "test -f /tmp/phase-cockpit-thirdparty-complete" 2>/dev/null; then
                echo "completed"
            else
                echo "not-started"
            fi
            ;;
        "cockpit-config")
            if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
                "test -f /tmp/cockpit-deployment-complete" 2>/dev/null; then
                echo "completed"
            else
                echo "not-started"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Show current deployment status
show_status() {
    echo ""
    echo "╭─────────────────────────────────────────────╮"
    echo "│          DEPLOYMENT STATUS                  │"
    echo "╰─────────────────────────────────────────────╯"
    
    if find_existing_instance; then
        echo "Instance ID: $INSTANCE_ID"
        echo "Public IP:   $PUBLIC_IP"
        echo ""
        echo "Phase Status:"
        echo "┌────────────────────────────────────┬──────────────┐"
        echo "│ Phase                              │ Status       │"
        echo "├────────────────────────────────────┼──────────────┤"
        
        local next_phase=""
        local deployment_complete=true
        
        for phase_info in "${PHASES[@]}"; do
            phase_name="${phase_info%%:*}"
            phase_desc="${phase_info##*:}"
            status=$(check_phase_status "$phase_name")
            
            case "$status" in
                "completed")
                    echo "│ $(printf '%-34s' "$phase_desc") │ ✅ Complete  │"
                    ;;
                "not-started")
                    echo "│ $(printf '%-34s' "$phase_desc") │ ⏸️  Pending   │"
                    if [[ -z "$next_phase" ]]; then
                        next_phase="$phase_name"
                    fi
                    deployment_complete=false
                    ;;
                *)
                    echo "│ $(printf '%-34s' "$phase_desc") │ ❓ Unknown   │"
                    deployment_complete=false
                    ;;
            esac
        done
        
        echo "└────────────────────────────────────┴──────────────┘"
        
        if [[ "$deployment_complete" == true ]]; then
            echo ""
            success "🎉 Deployment is COMPLETE!"
            if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" ]]; then
                echo "    Cockpit URL: https://$PUBLIC_IP:9090"
                echo "    Users: admin/rocky (Password: Cockpit123)"
            fi
        elif [[ -n "$next_phase" ]]; then
            echo ""
            log "Next phase to run: $next_phase"
            echo "    Resume with: ./launch-cockpit-instance-smart.sh --resume"
            echo "    Run phase:   ./launch-cockpit-instance-smart.sh --phase $next_phase"
        fi
    else
        echo "No existing instance found."
        echo ""
        log "Start new deployment: ./launch-cockpit-instance-smart.sh --force-new"
    fi
    echo ""
}

# Execute SSM phase
execute_ssm_phase() {
    local phase="$1"
    local phase_desc="$2"
    
    # Check if already completed
    local status=$(check_phase_status "$phase")
    if [[ "$status" == "completed" ]]; then
        success "$phase_desc already completed"
        return 0
    fi
    
    local doc_name=$(get_ssm_doc "$phase")
    if [[ -z "$doc_name" ]]; then
        error "No SSM document found for phase: $phase"
        return 1
    fi
    
    log "🚀 Starting $phase_desc..."
    
    # Send SSM command
    local command_id=$(aws ssm send-command \
        --region "$REGION" \
        --document-name "$doc_name" \
        --instance-ids "$INSTANCE_ID" \
        --parameters "snsTopicArn=$SNS_TOPIC_ARN,instanceId=$INSTANCE_ID" \
        --query 'Command.CommandId' \
        --output text)
    
    if [[ -z "$command_id" ]]; then
        error "Failed to start SSM command for $phase_desc"
        return 1
    fi
    
    log "Command ID: $command_id"
    log "Waiting for $phase_desc to complete..."
    
    # Monitor progress
    local attempts=0
    local max_attempts=120  # 60 minutes
    local status=""
    
    while [[ $attempts -lt $max_attempts ]]; do
        ((attempts++))
        
        status=$(aws ssm get-command-invocation \
            --region "$REGION" \
            --command-id "$command_id" \
            --instance-id "$INSTANCE_ID" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Unknown")
        
        case "$status" in
            "Success")
                success "✅ $phase_desc completed successfully"
                return 0
                ;;
            "Failed")
                error "❌ $phase_desc failed"
                echo "Error details:"
                aws ssm get-command-invocation \
                    --region "$REGION" \
                    --command-id "$command_id" \
                    --instance-id "$INSTANCE_ID" \
                    --query 'StandardErrorContent' \
                    --output text 2>/dev/null || echo "No error details available"
                return 1
                ;;
            "InProgress")
                if [[ $((attempts % 10)) -eq 0 ]]; then  # Log every 5 minutes
                    log "$phase_desc in progress... (${attempts}/2 attempts, $((attempts/2)) minutes)"
                fi
                sleep 30
                ;;
            *)
                sleep 30
                ;;
        esac
    done
    
    error "$phase_desc timed out after 60 minutes"
    return 1
}

# Main deployment logic
main() {
    echo "AWS Outpost Cockpit - Smart Idempotent Launcher"
    echo "==============================================="
    
    # Handle status-only request
    if [[ "$STATUS_ONLY" == true ]]; then
        show_status
        exit 0
    fi
    
    # Handle force new
    if [[ "$FORCE_NEW" == true ]]; then
        if find_existing_instance && [[ -n "$INSTANCE_ID" ]]; then
            log "Terminating existing instance: $INSTANCE_ID"
            aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
            log "Waiting for instance termination..."
            aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$INSTANCE_ID"
            success "Instance terminated"
        fi
        rm -f .last-instance-id
        INSTANCE_ID=""
        PUBLIC_IP=""
    fi
    
    # Find or create instance
    if ! find_existing_instance; then
        log "No existing instance found. Starting new deployment..."
        # Launch new instance (reuse existing functions)
        # ... (instance launch code from original script)
        error "Instance launching not implemented in this version yet"
        exit 1
    fi
    
    log "Found existing instance: $INSTANCE_ID ($PUBLIC_IP)"
    
    # Handle specific phase request
    if [[ -n "$SPECIFIC_PHASE" ]]; then
        # Find phase description
        local phase_desc=""
        for phase_info in "${PHASES[@]}"; do
            if [[ "${phase_info%%:*}" == "$SPECIFIC_PHASE" ]]; then
                phase_desc="${phase_info##*:}"
                break
            fi
        done
        
        if [[ -z "$phase_desc" ]]; then
            error "Unknown phase: $SPECIFIC_PHASE"
            echo "Use --list-phases to see available phases"
            exit 1
        fi
        
        if [[ "$SPECIFIC_PHASE" == "bootstrap" ]]; then
            error "Bootstrap phase cannot be run independently"
            exit 1
        fi
        
        execute_ssm_phase "$SPECIFIC_PHASE" "$phase_desc"
        exit $?
    fi
    
    # Default behavior: smart resume
    show_status
    
    log "Starting smart deployment resume..."
    
    # Execute phases in order, skipping completed ones
    local failed_phase=""
    for phase_info in "${PHASES[@]}"; do
        phase_name="${phase_info%%:*}"
        phase_desc="${phase_info##*:}"
        
        if [[ "$phase_name" == "bootstrap" ]]; then
            local status=$(check_phase_status "$phase_name")
            if [[ "$status" == "completed" ]]; then
                success "$phase_desc already completed"
            else
                error "$phase_desc not completed. Instance may not be ready."
                exit 1
            fi
            continue
        fi
        
        if ! execute_ssm_phase "$phase_name" "$phase_desc"; then
            failed_phase="$phase_name"
            break
        fi
    done
    
    if [[ -z "$failed_phase" ]]; then
        echo ""
        echo "╭─────────────────────────────────────────────╮"
        echo "│     🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!   │"
        echo "╰─────────────────────────────────────────────╯"
        echo "Instance ID: $INSTANCE_ID"
        if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" ]]; then
            echo "Cockpit URL: https://$PUBLIC_IP:9090"
            echo "Users: admin/rocky (Password: Cockpit123)"
        fi
        echo ""
    else
        echo ""
        error "Deployment failed at phase: $failed_phase"
        echo "Resume with: ./launch-cockpit-instance-smart.sh --resume"
        echo "Or run specific phase: ./launch-cockpit-instance-smart.sh --phase $failed_phase"
        exit 1
    fi
}

# Run main function
main "$@"