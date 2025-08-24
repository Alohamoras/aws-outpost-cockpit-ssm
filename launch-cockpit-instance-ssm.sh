#!/bin/bash

# AWS Outpost Cockpit Instance Launch Script - SSM Multi-Phase Architecture
# Launches EC2 instance with minimal user-data, then orchestrates SSM documents

set -e

# Load environment variables from .env file if it exists
if [[ -f .env ]]; then
    source .env
fi

# Configuration (defaults - can be overridden by .env file)
OUTPOST_ID="${OUTPOST_ID:-op-0c81637caaa70bcb8}"
SUBNET_ID="${SUBNET_ID:-subnet-0ccfe76ef0f0071f6}"
SECURITY_GROUP_ID="${SECURITY_GROUP_ID:-sg-03e548d8a756262fb}"
KEY_NAME="${KEY_NAME:-ryanfill}"
INSTANCE_TYPE="${INSTANCE_TYPE:-c6id.metal}"
REGION="${REGION:-us-east-1}"

# SNS Topic ARN for notifications (required)
SNS_TOPIC_ARN="${SNS_TOPIC_ARN}"

# SSH key file
KEY_FILE="${KEY_NAME}.pem"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
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
    log "Waiting for SSM agent to come online (up to 10 minutes)..."
    local ssm_ready=false
    local attempts=0
    local max_attempts=80  # 40 minutes at 30-second intervals
    
    while [[ $ssm_ready == false ]] && [[ $attempts -lt $max_attempts ]]; do
        ((attempts++))
        
        if aws ssm describe-instance-information \
            --region "$REGION" \
            --filters "Name=InstanceIds,Values=$INSTANCE_ID" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null | grep -q "Online"; then
            ssm_ready=true
            success "✅ SSM agent is online after $attempts attempts"
        else
            log "SSM attempt $attempts/$max_attempts - waiting 30 seconds..."
            sleep 30
        fi
    done
    
    if [[ $ssm_ready == false ]]; then
        error "SSM agent failed to come online after 10 minutes"
        exit 1
    fi
}

# Execute SSM document and wait for completion
execute_ssm_document() {
    local document_name="$1"
    local phase_name="$2"
    
    log "🚀 Executing $phase_name..."
    
    # Start SSM command
    COMMAND_ID=$(aws ssm send-command \
        --region "$REGION" \
        --document-name "$document_name" \
        --instance-ids "$INSTANCE_ID" \
        --parameters "snsTopicArn=$SNS_TOPIC_ARN,instanceId=$INSTANCE_ID" \
        --query 'Command.CommandId' \
        --output text)
    
    if [[ -z "$COMMAND_ID" ]]; then
        error "Failed to start SSM command for $phase_name"
        return 1
    fi
    
    log "Command ID: $COMMAND_ID"
    
    # Wait for command completion
    log "Waiting for $phase_name to complete..."
    local status=""
    local attempts=0
    local max_attempts=60  # 30 minutes at 30-second intervals
    
    while [[ $attempts -lt $max_attempts ]]; do
        ((attempts++))
        
        status=$(aws ssm get-command-invocation \
            --region "$REGION" \
            --command-id "$COMMAND_ID" \
            --instance-id "$INSTANCE_ID" \
            --query 'Status' \
            --output text 2>/dev/null)
        
        case "$status" in
            "Success")
                success "✅ $phase_name completed successfully"
                return 0
                ;;
            "Failed")
                error "❌ $phase_name failed"
                # Show error output
                aws ssm get-command-invocation \
                    --region "$REGION" \
                    --command-id "$COMMAND_ID" \
                    --instance-id "$INSTANCE_ID" \
                    --query 'StandardErrorContent' \
                    --output text
                return 1
                ;;
            "InProgress")
                log "$phase_name in progress (attempt $attempts/$max_attempts)..."
                sleep 30
                ;;
            *)
                log "$phase_name status: $status (attempt $attempts/$max_attempts)..."
                sleep 30
                ;;
        esac
    done
    
    error "$phase_name timed out after 30 minutes"
    return 1
}

# Execute all phases in sequence
execute_deployment_phases() {
    log "🎯 Starting multi-phase Cockpit deployment..."
    
    # Phase 1: System Updates
    if ! execute_ssm_document "outpost-system-updates" "System Updates"; then
        error "System updates failed - deployment cannot continue"
        exit 1
    fi
    
    # Phase 2: Core Cockpit Installation
    if ! execute_ssm_document "outpost-cockpit-core" "Core Cockpit Installation"; then
        error "Core Cockpit installation failed - deployment cannot continue"
        exit 1
    fi
    
    # Phase 3: Cockpit Extensions (non-critical)
    if ! execute_ssm_document "outpost-cockpit-extensions" "Cockpit Extensions"; then
        warning "Cockpit extensions installation had issues - continuing..."
    fi
    
    # Phase 4: Third-party Extensions (non-critical)
    if ! execute_ssm_document "outpost-cockpit-thirdparty" "Third-party Extensions"; then
        warning "Third-party extensions installation had issues - continuing..."
    fi
    
    # Phase 5: Final Configuration
    if ! execute_ssm_document "outpost-cockpit-config" "Final Configuration"; then
        error "Final configuration failed"
        exit 1
    fi
    
    success "🎉 All deployment phases completed successfully!"
}

# Show final deployment summary
show_deployment_summary() {
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "🎉 COCKPIT DEPLOYMENT COMPLETED SUCCESSFULLY! (SSM ARCHITECTURE)"
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
    echo "AWS Outpost Cockpit Launch - SSM Multi-Phase Architecture"
    echo "========================================================="
    
    check_prerequisites
    create_ssm_documents
    get_latest_ami
    ensure_ssm_instance_profile
    launch_instance
    wait_for_instance_ready
    execute_deployment_phases
    show_deployment_summary
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"