#!/bin/bash

# SSM Command Monitoring Script
# Monitors single SSM command execution progress in real-time

set -e

# Configuration
COMMAND_ID="${1:-}"
INSTANCE_ID="${2:-}"
CHECK_INTERVAL=30  # Check every 30 seconds
MAX_WAIT_TIME=3600  # Maximum 60 minutes

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

# Get command status
get_command_status() {
    aws ssm get-command-invocation \
        --region "$REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --query '[Status,StatusDetails,StandardOutputContent]' \
        --output text 2>/dev/null || echo "UNKNOWN None None"
}

# Display progress summary
display_progress() {
    local status="$1"
    local status_details="$2"
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo -e "${PURPLE}🚀 COCKPIT COMMAND MONITOR${NC}"
    echo "═══════════════════════════════════════════════════"
    echo "Command ID: $COMMAND_ID"
    echo "Instance ID: $INSTANCE_ID"
    echo "Status: $status"
    echo "Details: $status_details"
    echo "Check Time: $(date)"
    echo "═══════════════════════════════════════════════════"
}

# Parse component progress from output
display_component_progress() {
    local output="$1"
    
    echo ""
    echo "📋 Component Progress:"
    echo "─────────────────────────────────────────────────"
    
    # Extract component progress from the log output
    if echo "$output" | grep -q "COMPONENT 1: SYSTEM PREPARATION"; then
        if echo "$output" | grep -q "System preparation completed successfully"; then
            echo -e "  ✅ ${GREEN}System Preparation${NC} - Complete"
        else
            echo -e "  🔄 ${CYAN}System Preparation${NC} - In Progress"
            return
        fi
    else
        echo -e "  ⏳ System Preparation - Pending"
        return
    fi
    
    if echo "$output" | grep -q "COMPONENT 2: CORE COCKPIT INSTALLATION"; then
        if echo "$output" | grep -q "Core Cockpit installation completed"; then
            echo -e "  ✅ ${GREEN}Core Cockpit Installation${NC} - Complete"
        else
            echo -e "  🔄 ${CYAN}Core Cockpit Installation${NC} - In Progress"
            return
        fi
    else
        echo -e "  ⏳ Core Cockpit Installation - Pending"
        return
    fi
    
    if echo "$output" | grep -q "COMPONENT 3: EXTENDED SERVICES SETUP"; then
        if echo "$output" | grep -q "Extended services setup completed"; then
            echo -e "  ✅ ${GREEN}Extended Services Setup${NC} - Complete"
        else
            echo -e "  🔄 ${CYAN}Extended Services Setup${NC} - In Progress"
            return
        fi
    else
        echo -e "  ⏳ Extended Services Setup - Pending"
        return
    fi
    
    if echo "$output" | grep -q "COMPONENT 4: THIRD-PARTY EXTENSIONS"; then
        if echo "$output" | grep -q "Third-party extensions installation completed"; then
            echo -e "  ✅ ${GREEN}Third-party Extensions${NC} - Complete"
        else
            echo -e "  🔄 ${CYAN}Third-party Extensions${NC} - In Progress"
            return
        fi
    else
        echo -e "  ⏳ Third-party Extensions - Pending"
        return
    fi
    
    if echo "$output" | grep -q "COMPONENT 5: USER CONFIGURATION"; then
        if echo "$output" | grep -q "User configuration completed"; then
            echo -e "  ✅ ${GREEN}User Configuration${NC} - Complete"
        else
            echo -e "  🔄 ${CYAN}User Configuration${NC} - In Progress"
            return
        fi
    else
        echo -e "  ⏳ User Configuration - Pending"
        return
    fi
    
    if echo "$output" | grep -q "COMPONENT 6: FINAL CONFIGURATION"; then
        if echo "$output" | grep -q "Final configuration completed"; then
            echo -e "  ✅ ${GREEN}Final Configuration${NC} - Complete"
        else
            echo -e "  🔄 ${CYAN}Final Configuration${NC} - In Progress"
            return
        fi
    else
        echo -e "  ⏳ Final Configuration - Pending"
        return
    fi
}

# Get estimated completion time
estimate_completion() {
    local output="$1"
    
    if echo "$output" | grep -q "COMPONENT 1: SYSTEM PREPARATION"; then
        echo "⏱️  Estimated time remaining: ~45-55 minutes"
    elif echo "$output" | grep -q "COMPONENT 2: CORE COCKPIT INSTALLATION"; then
        echo "⏱️  Estimated time remaining: ~35-45 minutes"
    elif echo "$output" | grep -q "COMPONENT 3: EXTENDED SERVICES SETUP"; then
        echo "⏱️  Estimated time remaining: ~25-35 minutes"
    elif echo "$output" | grep -q "COMPONENT 4: THIRD-PARTY EXTENSIONS"; then
        echo "⏱️  Estimated time remaining: ~15-25 minutes"
    elif echo "$output" | grep -q "COMPONENT 5: USER CONFIGURATION"; then
        echo "⏱️  Estimated time remaining: ~5-10 minutes"
    elif echo "$output" | grep -q "COMPONENT 6: FINAL CONFIGURATION"; then
        echo "⏱️  Estimated time remaining: ~1-5 minutes"
    fi
}

# Main monitoring function
monitor_command() {
    if [[ -z "$COMMAND_ID" || -z "$INSTANCE_ID" ]]; then
        error "Usage: $0 <command-id> <instance-id>"
        exit 1
    fi
    
    log "Starting command monitoring for: $COMMAND_ID"
    log "Instance: $INSTANCE_ID"
    log "Checking status every $CHECK_INTERVAL seconds..."
    
    local start_time=$(date +%s)
    local last_status=""
    local check_count=0
    
    while true; do
        ((check_count++))
        
        # Get current status
        local status_info=$(get_command_status)
        local status=$(echo "$status_info" | cut -f1)
        local status_details=$(echo "$status_info" | cut -f2)
        local output=$(echo "$status_info" | cut -f3-)
        
        # Display progress if status changed or every 5 checks
        if [[ "$status" != "$last_status" || $((check_count % 5)) -eq 0 ]]; then
            display_progress "$status" "$status_details"
            display_component_progress "$output"
            estimate_completion "$output"
            
            # Status change notifications
            if [[ "$status" != "$last_status" ]]; then
                case "$status" in
                    "Success")
                        success "🎉 Command completed successfully!"
                        ;;
                    "Failed")
                        error "💥 Command failed!"
                        ;;
                    "TimedOut")
                        warning "⏰ Command timed out!"
                        ;;
                    "InProgress")
                        progress "🔄 Command is progressing..."
                        ;;
                esac
            fi
            
            last_status="$status"
        else
            # Brief status update
            log "Status: $status | Check: $check_count"
        fi
        
        # Check if command is complete
        case "$status" in
            "Success"|"Failed"|"TimedOut"|"Cancelled")
                echo ""
                echo "═══════════════════════════════════════════════════"
                if [[ "$status" == "Success" ]]; then
                    success "🎉 COMMAND COMPLETED SUCCESSFULLY!"
                    echo ""
                    echo "🌐 Access Cockpit at: https://<instance-ip>:9090"
                    echo "👤 Login: admin / Password: Cockpit123"
                    echo "👤 Login: rocky / Password: Cockpit123"
                    echo ""
                    echo "🔧 Management commands:"
                    echo "  Check status: systemctl status cockpit.socket"
                    echo "  View logs: sudo tail -f /var/log/cockpit-complete-install.log"
                else
                    error "💥 COMMAND ENDED WITH STATUS: $status"
                    echo ""
                    echo "🔧 Troubleshooting:"
                    echo "  Check logs: ssh -i ryanfill.pem rocky@<instance-ip> 'sudo tail -f /var/log/cockpit-complete-install.log'"
                    echo "  Retry command: aws ssm send-command --document-name cockpit-complete-install --instance-ids $INSTANCE_ID"
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
            warning "Command may still be running. Check AWS Console or continue monitoring manually."
            break
        fi
        
        # Wait before next check
        sleep $CHECK_INTERVAL
    done
}

# Run monitoring
monitor_command