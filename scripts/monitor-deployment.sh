#!/bin/bash

# SSM Deployment Monitoring Script
# Monitors Cockpit deployment progress in real-time

set -e

# Configuration
EXECUTION_ID="${1:-}"
CHECK_INTERVAL=30  # Check every 30 seconds
MAX_WAIT_TIME=10800  # Maximum 180 minutes (3 hours)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ -f "$PROJECT_ROOT/.env" ]]; then
    source "$PROJECT_ROOT/.env"
fi

REGION="${REGION:-us-east-1}"

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $1"
}

progress() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')] 🔄${NC} $1"
}

# Get execution status
get_execution_status() {
    aws ssm describe-automation-executions \
        --region "$REGION" \
        --filters "Key=ExecutionId,Values=$EXECUTION_ID" \
        --query 'AutomationExecutions[0].[AutomationExecutionStatus,CurrentStepName,FailureMessage]' \
        --output text 2>/dev/null || echo "UNKNOWN None None"
}

# Get step details
get_step_details() {
    aws ssm describe-automation-step-executions \
        --region "$REGION" \
        --automation-execution-id "$EXECUTION_ID" \
        --query 'StepExecutions[*].[StepName,StepStatus,ExecutionStartTime,ExecutionEndTime]' \
        --output text 2>/dev/null
}

# Display progress summary
display_progress() {
    local status="$1"
    local current_step="$2"
    local failure_msg="$3"
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo -e "${PURPLE}🚀 COCKPIT DEPLOYMENT MONITOR${NC}"
    echo "═══════════════════════════════════════════════════"
    echo "Execution ID: $EXECUTION_ID"
    echo "Overall Status: $status"
    echo "Current Step: $current_step"
    echo "Check Time: $(date)"
    echo "═══════════════════════════════════════════════════"
    
    if [[ -n "$failure_msg" && "$failure_msg" != "None" ]]; then
        error "Failure Message: $failure_msg"
    fi
}

# Display step details
display_step_details() {
    local steps_output="$1"
    
    echo ""
    echo "📋 Component Status:"
    echo "─────────────────────────────────────────────────"
    
    # Track completed, in progress, and pending counts
    local completed=0
    local in_progress=0
    local failed=0
    local pending=0
    
    # Core components in order
    local core_steps=("ValidateInstance" "CheckInstanceRunning" "NotifyStart" "SystemPreparation" "CoreCockpitInstall" "ExtendedServicesSetup" "ThirdPartyExtensions" "UserConfiguration" "FinalConfiguration")
    
    while IFS=$'\t' read -r step_name step_status start_time end_time; do
        # Skip empty lines and error handler steps
        if [[ -z "$step_name" || "$step_name" == *"Failure"* || "$step_name" == *"FailureStop"* || "$step_name" == "InstanceNotRunning" ]]; then
            continue
        fi
        
        # Format timing
        local timing=""
        if [[ "$start_time" != "None" && -n "$start_time" ]]; then
            local start_formatted=$(date -d "$start_time" '+%H:%M:%S' 2>/dev/null || echo "${start_time##*T}" | cut -d'+' -f1 | cut -d'.' -f1)
            if [[ "$end_time" != "None" && -n "$end_time" ]]; then
                local end_formatted=$(date -d "$end_time" '+%H:%M:%S' 2>/dev/null || echo "${end_time##*T}" | cut -d'+' -f1 | cut -d'.' -f1)
                timing="($start_formatted → $end_formatted)"
            else
                timing="(started $start_formatted)"
            fi
        fi
        
        # Display status with appropriate icon and color
        case "$step_status" in
            "Success")
                echo -e "  ✅ ${GREEN}$step_name${NC} $timing"
                ((completed++))
                ;;
            "InProgress")
                echo -e "  🔄 ${CYAN}$step_name${NC} $timing"
                ((in_progress++))
                ;;
            "Failed")
                echo -e "  ❌ ${RED}$step_name${NC} $timing"
                ((failed++))
                ;;
            "TimedOut")
                echo -e "  ⏰ ${YELLOW}$step_name${NC} $timing"
                ((failed++))
                ;;
            "Cancelled")
                echo -e "  🚫 ${YELLOW}$step_name${NC} $timing"
                ((failed++))
                ;;
            "Pending"|*)
                if [[ "$step_name" =~ ^(ValidateInstance|CheckInstanceRunning|NotifyStart|SystemPreparation|CoreCockpitInstall|ExtendedServicesSetup|ThirdPartyExtensions|UserConfiguration|FinalConfiguration)$ ]]; then
                    echo -e "  ⏳ ${step_name} (pending)"
                    ((pending++))
                fi
                ;;
        esac
    done <<< "$steps_output"
    
    echo "─────────────────────────────────────────────────"
    echo -e "📊 Progress: ${GREEN}$completed completed${NC}, ${CYAN}$in_progress active${NC}, ${YELLOW}$pending pending${NC}"
    if [[ $failed -gt 0 ]]; then
        echo -e "⚠️  ${RED}$failed failed components${NC}"
    fi
}

# Get estimated completion time
estimate_completion() {
    local status="$1"
    local current_step="$2"
    
    case "$current_step" in
        "SystemPreparation")
            echo "⏱️  Estimated time remaining: ~20-30 minutes"
            ;;
        "CoreCockpitInstall")
            echo "⏱️  Estimated time remaining: ~15-25 minutes"
            ;;
        "ExtendedServicesSetup")
            echo "⏱️  Estimated time remaining: ~10-20 minutes (virtualization takes time)"
            ;;
        "ThirdPartyExtensions")
            echo "⏱️  Estimated time remaining: ~5-10 minutes"
            ;;
        "UserConfiguration")
            echo "⏱️  Estimated time remaining: ~3-5 minutes"
            ;;
        "FinalConfiguration")
            echo "⏱️  Estimated time remaining: ~1-3 minutes"
            ;;
        *)
            if [[ "$status" == "InProgress" ]]; then
                echo "⏱️  Estimated time remaining: ~5-15 minutes"
            fi
            ;;
    esac
}

# Main monitoring function
monitor_deployment() {
    if [[ -z "$EXECUTION_ID" ]]; then
        error "Usage: $0 <execution-id>"
        exit 1
    fi
    
    log "Starting deployment monitoring for execution: $EXECUTION_ID"
    log "Checking status every $CHECK_INTERVAL seconds..."
    
    local start_time=$(date +%s)
    local last_status=""
    local last_step=""
    local check_count=0
    
    while true; do
        ((check_count++))
        
        # Get current status
        local status_info=$(get_execution_status)
        local status=$(echo "$status_info" | cut -f1)
        local current_step=$(echo "$status_info" | cut -f2)
        local failure_msg=$(echo "$status_info" | cut -f3)
        
        # Get step details
        local steps_output=$(get_step_details)
        
        # Display progress (only if status changed or every 5 checks)
        if [[ "$status" != "$last_status" || "$current_step" != "$last_step" || $((check_count % 5)) -eq 0 ]]; then
            display_progress "$status" "$current_step" "$failure_msg"
            display_step_details "$steps_output"
            estimate_completion "$status" "$current_step"
            
            # Status change notifications
            if [[ "$status" != "$last_status" ]]; then
                case "$status" in
                    "Success")
                        success "🎉 Deployment completed successfully!"
                        ;;
                    "Failed")
                        error "💥 Deployment failed!"
                        ;;
                    "TimedOut")
                        warning "⏰ Deployment timed out!"
                        ;;
                    "InProgress")
                        progress "🔄 Deployment is progressing..."
                        ;;
                esac
            fi
            
            last_status="$status"
            last_step="$current_step"
        else
            # Brief status update
            log "Status: $status | Step: $current_step | Check: $check_count"
        fi
        
        # Check if deployment is complete
        case "$status" in
            "Success"|"Failed"|"TimedOut"|"Cancelled")
                echo ""
                echo "═══════════════════════════════════════════════════"
                if [[ "$status" == "Success" ]]; then
                    success "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
                    echo ""
                    echo "🌐 Access Cockpit at: https://35.172.117.145:9090"
                    echo "👤 Login: admin / Password: Cockpit123"
                    echo "👤 Login: rocky / Password: Cockpit123"
                    echo ""
                    echo "🔧 Management commands:"
                    echo "  ./legacy/manage-instances.sh cockpit  # Open in browser"
                    echo "  ./legacy/manage-instances.sh services # Check health"
                else
                    error "💥 DEPLOYMENT ENDED WITH STATUS: $status"
                    if [[ -n "$failure_msg" && "$failure_msg" != "None" ]]; then
                        error "Failure: $failure_msg"
                    fi
                    echo ""
                    echo "🔧 Troubleshooting:"
                    echo "  Check logs: ssh -i ryanfill.pem rocky@35.172.117.145 'sudo tail -f /var/log/cockpit-*.log'"
                    echo "  Retry components individually using the commands shown earlier"
                fi
                echo "═══════════════════════════════════════════════════"
                
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                log "Total monitoring time: $((duration / 60)) minutes $((duration % 60)) seconds"
                break
                ;;
        esac
        
        # Timeout check
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -gt $MAX_WAIT_TIME ]]; then
            warning "⏰ Monitoring timeout reached ($((MAX_WAIT_TIME / 60)) minutes)"
            warning "Deployment may still be running. Check AWS Console or continue monitoring manually."
            break
        fi
        
        # Wait before next check
        sleep $CHECK_INTERVAL
    done
}

# Run monitoring
monitor_deployment