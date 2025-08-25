#!/bin/bash

# AWS Outpost Cockpit Instance Launch Script - Complete SSM Multi-Phase Architecture
# Smart idempotent launcher with full instance launching and resume capabilities

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
    "storage-config:Storage Configuration"
    "cockpit-core:Core Cockpit Installation"
    "cockpit-extensions:Cockpit Extensions"
    "cockpit-thirdparty:Third-party Extensions"  
    "cockpit-config:Final Configuration"
)

# SSM document mapping function
get_ssm_doc() {
    case "$1" in
        "system-updates") echo "outpost-system-updates" ;;
        "storage-config") echo "outpost-storage-config" ;;
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
AWS Outpost Cockpit Deployment - Complete SSM Multi-Phase Launcher

USAGE:
    ./launch-cockpit-instance.sh [OPTIONS]

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
    storage-config         Storage configuration (RAID5 + root extension)
    cockpit-core          Core Cockpit installation
    cockpit-extensions    Virtualization, containers, monitoring
    cockpit-thirdparty    45Drives extensions
    cockpit-config        Final configuration

EXAMPLES:
    # Smart detection and launch/resume (default)
    ./launch-cockpit-instance.sh
    
    # Check current status
    ./launch-cockpit-instance.sh --status
    
    # Resume from failure
    ./launch-cockpit-instance.sh --resume
    
    # Run specific phase only
    ./launch-cockpit-instance.sh --phase cockpit-core
    
    # Start completely fresh
    ./launch-cockpit-instance.sh --force-new

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
        "storage-config")
            if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
                "test -f /tmp/phase-storage-config-complete" 2>/dev/null; then
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
            echo "    Resume with: ./launch-cockpit-instance.sh --resume"
            echo "    Run phase:   ./launch-cockpit-instance.sh --phase $next_phase"
        fi
    else
        echo "No existing instance found."
        echo ""
        log "Start new deployment: ./launch-cockpit-instance.sh --force-new"
        log "Or launch with: ./launch-cockpit-instance.sh"
    fi
    echo ""
}

# Pre-flight checks
check_prerequisites() {
    log "Running pre-flight checks..."
    
    # Check required environment variables
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        error "SNS_TOPIC_ARN is required but not set in .env file"
        exit 1
    fi
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check SSH key
    if [[ ! -f "$KEY_FILE" ]]; then
        error "SSH key file '$KEY_FILE' not found"
        error "Please copy your private key to the current directory"
        exit 1
    fi
    chmod 400 "$KEY_FILE"
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured properly"
        exit 1
    fi
    
    success "All prerequisites met"
}

# Create or verify SSM documents exist
create_ssm_documents() {
    log "Creating/verifying SSM documents..."
    
    local documents=(
        "outpost-system-updates"
        "outpost-storage-config"
        "outpost-cockpit-core"
        "outpost-cockpit-extensions"
        "outpost-cockpit-thirdparty"
        "outpost-cockpit-config"
    )
    
    for doc in "${documents[@]}"; do
        local doc_file="ssm-documents/${doc}.json"
        
        if [[ ! -f "$doc_file" ]]; then
            error "SSM document file not found: $doc_file"
            exit 1
        fi
        
        log "Creating/updating SSM document: $doc"
        
        # Try to create the document, or update if it already exists
        if aws ssm create-document \
            --region "$REGION" \
            --name "$doc" \
            --document-type "Command" \
            --content "file://$doc_file" >/dev/null 2>&1; then
            success "Created SSM document: $doc"
        else
            # Document might already exist, try to update
            if aws ssm update-document \
                --region "$REGION" \
                --name "$doc" \
                --content "file://$doc_file" \
                --document-version '$LATEST' >/dev/null 2>&1; then
                success "Updated SSM document: $doc"
            else
                warning "SSM document $doc already exists and up to date"
            fi
        fi
    done
}

# Get latest Rocky Linux 9 AMI
get_latest_ami() {
    log "Finding latest Rocky Linux 9 AMI..."
    
    AMI_ID=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners 679593333241 \
        --filters "Name=name,Values=Rocky-9-EC2-LVM-*" \
                  "Name=architecture,Values=x86_64" \
                  "Name=virtualization-type,Values=hvm" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [[ "$AMI_ID" == "None" ]] || [[ -z "$AMI_ID" ]]; then
        error "Failed to find Rocky Linux 9 AMI"
        exit 1
    fi
    
    success "Found AMI: $AMI_ID"
}

# Ensure SSM instance profile exists
ensure_ssm_instance_profile() {
    log "Checking for SSM instance profile..."
    
    local profile_created=false
    
    # Check if instance profile exists
    if aws iam get-instance-profile --instance-profile-name "CockpitSSMInstanceProfile" >/dev/null 2>&1; then
        success "SSM instance profile already exists"
    else
        profile_created=true
        log "Creating SSM instance profile..."
        
        # Create the instance profile
        aws iam create-instance-profile \
            --instance-profile-name "CockpitSSMInstanceProfile" \
            --path "/" >/dev/null
        
        # Add the SSM managed role to the instance profile
        aws iam add-role-to-instance-profile \
            --instance-profile-name "CockpitSSMInstanceProfile" \
            --role-name "AmazonSSMManagedInstanceCore" 2>/dev/null || {
            
            # If role doesn't exist, create it
            log "Creating SSM role..."
            aws iam create-role \
                --role-name "AmazonSSMManagedInstanceCore" \
                --assume-role-policy-document '{
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Effect": "Allow",
                            "Principal": {
                                "Service": "ec2.amazonaws.com"
                            },
                            "Action": "sts:AssumeRole"
                        }
                    ]
                }' >/dev/null
            
            # Attach the SSM managed policy
            aws iam attach-role-policy \
                --role-name "AmazonSSMManagedInstanceCore" \
                --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" >/dev/null
            
            # Create and attach SNS policy for notifications
            aws iam put-role-policy \
                --role-name "AmazonSSMManagedInstanceCore" \
                --policy-name "CockpitSNSNotifications" \
                --policy-document "{
                    \"Version\": \"2012-10-17\",
                    \"Statement\": [
                        {
                            \"Effect\": \"Allow\",
                            \"Action\": \"sns:Publish\",
                            \"Resource\": \"$SNS_TOPIC_ARN\"
                        }
                    ]
                }" >/dev/null
            
            # Add role to instance profile
            aws iam add-role-to-instance-profile \
                --instance-profile-name "CockpitSSMInstanceProfile" \
                --role-name "AmazonSSMManagedInstanceCore" >/dev/null
        }
    fi
    
    # Wait for IAM propagation if we created new resources
    if [[ $profile_created == true ]]; then
        log "Waiting 30 seconds for IAM propagation..."
        sleep 30
    fi
    
    success "SSM instance profile configured"
}

# Launch EC2 instance with minimal user-data
launch_instance() {
    log "Launching EC2 instance with minimal bootstrap..."
    
    # Load minimal user-data from bootstrap script file
    if [[ ! -f "user-data-minimal.sh" ]]; then
        error "user-data-minimal.sh file not found"
        exit 1
    fi
    
    # Prepare user-data with SNS topic ARN substitution
    local user_data="$(cat user-data-minimal.sh)"
    
    # Replace the placeholder with actual SNS topic ARN from .env
    user_data="${user_data//\{\{SNS_TOPIC_ARN\}\}/$SNS_TOPIC_ARN}"
    
    log "SNS topic ARN configured for bootstrap notifications"
    
    INSTANCE_ID=$(aws ec2 run-instances \
        --region "$REGION" \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --subnet-id "$SUBNET_ID" \
        --iam-instance-profile "Name=CockpitSSMInstanceProfile" \
        --user-data "$user_data" \
        --placement "AvailabilityZone=$(aws ec2 describe-subnets --region $REGION --subnet-ids $SUBNET_ID --query 'Subnets[0].AvailabilityZone' --output text)" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Cockpit-Outpost-Server-SSM},{Key=Purpose,Value=Cockpit-WebConsole},{Key=CockpitNotificationTopic,Value=$SNS_TOPIC_ARN},{Key=CockpitAutomation,Value=SSM-MultiPhase}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [[ -z "$INSTANCE_ID" ]]; then
        error "Failed to launch instance"
        exit 1
    fi
    
    success "Instance launched: $INSTANCE_ID"
    echo "Instance ID: $INSTANCE_ID" > .last-instance-id
    echo "Architecture: SSM Multi-Phase" >> .last-instance-id
}

# Wait for instance to be ready and SSM to be available
wait_for_instance_ready() {
    log "Waiting for instance to be ready for SSM execution..."
    
    # Wait for instance to be running
    log "Waiting for instance to reach 'running' state..."
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
    success "✅ Instance is running"
    
    # Get public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null)
    
    if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
        log "No public IP assigned, attempting to assign Elastic IP..."
        
        local available_eip=$(aws ec2 describe-addresses \
            --region "$REGION" \
            --query 'Addresses[?InstanceId==null && NetworkInterfaceId==null] | [0].AllocationId' \
            --output text 2>/dev/null)
        
        if [[ -n "$available_eip" && "$available_eip" != "None" ]]; then
            aws ec2 associate-address \
                --region "$REGION" \
                --instance-id "$INSTANCE_ID" \
                --allocation-id "$available_eip" >/dev/null
            
            PUBLIC_IP=$(aws ec2 describe-instances \
                --region "$REGION" \
                --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' \
                --output text 2>/dev/null)
        fi
    fi
    
    if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" ]]; then
        success "✅ Public IP assigned: $PUBLIC_IP"
        echo "Public IP: $PUBLIC_IP" >> .last-instance-id
    else
        warning "No public IP available - instance accessible via private IP only"
    fi
    
    # Wait for SSM agent to be online
    log "Waiting for SSM agent to come online (up to 40 minutes)..."
    local ssm_ready=false
    local attempts=0
    local max_attempts=80  # 40 minutes at 30-second intervals
    
    while [[ $ssm_ready == false ]] && [[ $attempts -lt $max_attempts ]]; do
        ((attempts++))
        
        if aws ssm describe-instance-information \
            --region "$REGION" \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null | grep -q "Online"; then
            ssm_ready=true
            success "✅ SSM agent is online after $attempts attempts"
        else
            if [[ $((attempts % 10)) -eq 0 ]]; then  # Log every 5 minutes
                log "SSM attempt $attempts/$max_attempts - waiting 30 seconds... ($((attempts/2)) minutes elapsed)"
            fi
            sleep 30
        fi
    done
    
    if [[ $ssm_ready == false ]]; then
        error "SSM agent failed to come online after 40 minutes"
        exit 1
    fi
}

# Execute SSM document and wait for completion
execute_ssm_document() {
    local document_name="$1"
    local phase_desc="$2"
    
    log "🚀 Executing $phase_desc..."
    
    # Start SSM command
    COMMAND_ID=$(aws ssm send-command \
        --region "$REGION" \
        --document-name "$document_name" \
        --instance-ids "$INSTANCE_ID" \
        --parameters "snsTopicArn=$SNS_TOPIC_ARN,instanceId=$INSTANCE_ID" \
        --query 'Command.CommandId' \
        --output text)
    
    if [[ -z "$COMMAND_ID" ]]; then
        error "Failed to start SSM command for $phase_desc"
        return 1
    fi
    
    log "Command ID: $COMMAND_ID"
    
    # Wait for command completion
    log "Waiting for $phase_desc to complete..."
    local status=""
    local attempts=0
    local max_attempts=120  # 60 minutes at 30-second intervals
    
    while [[ $attempts -lt $max_attempts ]]; do
        ((attempts++))
        
        status=$(aws ssm get-command-invocation \
            --region "$REGION" \
            --command-id "$COMMAND_ID" \
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

# Execute SSM phase with completion checking
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
    
    execute_ssm_document "$doc_name" "$phase_desc"
}

# Execute all phases in sequence
execute_deployment_phases() {
    log "🎯 Starting multi-phase Cockpit deployment..."
    
    # Phase 1: System Updates
    if ! execute_ssm_phase "system-updates" "System Updates"; then
        error "System updates failed - deployment cannot continue"
        exit 1
    fi
    
    # Phase 2: Storage Configuration (non-critical - continues on failure)
    if ! execute_ssm_phase "storage-config" "Storage Configuration"; then
        warning "Storage configuration had issues - continuing deployment..."
    fi
    
    # Phase 3: Core Cockpit Installation
    if ! execute_ssm_phase "cockpit-core" "Core Cockpit Installation"; then
        error "Core Cockpit installation failed - deployment cannot continue"
        exit 1
    fi
    
    # Phase 4: Cockpit Extensions (non-critical)
    if ! execute_ssm_phase "cockpit-extensions" "Cockpit Extensions"; then
        warning "Cockpit extensions installation had issues - continuing..."
    fi
    
    # Phase 5: Third-party Extensions (non-critical)
    if ! execute_ssm_phase "cockpit-thirdparty" "Third-party Extensions"; then
        warning "Third-party extensions installation had issues - continuing..."
    fi
    
    # Phase 6: Final Configuration
    if ! execute_ssm_phase "cockpit-config" "Final Configuration"; then
        error "Final configuration failed"
        exit 1
    fi
    
    success "🎉 All deployment phases completed successfully!"
}

# Show final deployment summary
show_deployment_summary() {
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "🎉 COCKPIT DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "══════════════════════════════════════════════════════════"
    echo "Instance ID: $INSTANCE_ID"
    if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" ]]; then
        echo "Public IP: $PUBLIC_IP"
        echo "Cockpit URL: https://$PUBLIC_IP:9090"
    else
        echo "Access: Private IP only (check AWS console for private IP)"
    fi
    echo "Users: admin/rocky (Password: Cockpit123)"
    echo "Architecture: SSM Multi-Phase"
    echo "Completion Time: $(date)"
    echo ""
    echo "Management Commands:"
    echo "  Monitor logs: ./legacy/manage-instances.sh logs"
    echo "  SSH access: ./legacy/manage-instances.sh ssh"
    if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" ]]; then
        echo "  Web interface: ./legacy/manage-instances.sh cockpit"
    fi
    echo "══════════════════════════════════════════════════════════"
    echo ""
}

# Main execution
main() {
    echo "AWS Outpost Cockpit Launch - Complete SSM Multi-Phase Architecture"
    echo "=================================================================="
    
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
    
    # Handle specific phase request
    if [[ -n "$SPECIFIC_PHASE" ]]; then
        # Verify we have an existing instance
        if ! find_existing_instance; then
            error "No existing instance found. Cannot run specific phase."
            error "Use --force-new to launch new instance first."
            exit 1
        fi
        
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
        
        log "Found existing instance: $INSTANCE_ID ($PUBLIC_IP)"
        execute_ssm_phase "$SPECIFIC_PHASE" "$phase_desc"
        exit $?
    fi
    
    # Default behavior: smart launch or resume
    if find_existing_instance; then
        log "Found existing instance: $INSTANCE_ID ($PUBLIC_IP)"
        show_status
        
        # Check if deployment is complete
        local deployment_complete=true
        local next_phase=""
        
        for phase_info in "${PHASES[@]}"; do
            phase_name="${phase_info%%:*}"
            if [[ "$phase_name" == "bootstrap" ]]; then
                continue  # Skip bootstrap check
            fi
            
            local status=$(check_phase_status "$phase_name")
            if [[ "$status" != "completed" ]]; then
                deployment_complete=false
                if [[ -z "$next_phase" ]]; then
                    next_phase="$phase_name"
                fi
            fi
        done
        
        if [[ "$deployment_complete" == true ]]; then
            success "🎉 Deployment is already complete!"
            exit 0
        fi
        
        log "Starting smart deployment resume..."
        
        # Execute remaining phases in order, skipping completed ones
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
            show_deployment_summary
        else
            echo ""
            error "Deployment failed at phase: $failed_phase"
            echo "Resume with: ./launch-cockpit-instance.sh --resume"
            echo "Or run specific phase: ./launch-cockpit-instance.sh --phase $failed_phase"
            exit 1
        fi
    else
        log "No existing instance found. Starting new deployment..."
        
        check_prerequisites
        create_ssm_documents
        get_latest_ami
        ensure_ssm_instance_profile
        launch_instance
        wait_for_instance_ready
        execute_deployment_phases
        show_deployment_summary
    fi
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"