#!/bin/bash

# AWS Outpost Cockpit Instance Launch Script - SSM Architecture
# Launches EC2 instance and triggers SSM automation for Cockpit installation

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

# SSM Document name - Modular architecture using orchestration
SSM_MAIN_DOCUMENT="${SSM_MAIN_DOCUMENT:-cockpit-deploy-automation}"

# SNS Topic ARN for notifications (required)
SNS_TOPIC_ARN="${SNS_TOPIC_ARN}"

# Deployment options (can be overridden by .env file)
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-true}"
AUTOMATION_ASSUME_ROLE="${AUTOMATION_ASSUME_ROLE:-}"

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check SNS Topic ARN is provided
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        error "SNS_TOPIC_ARN environment variable is required for notifications."
        error "Set it with: export SNS_TOPIC_ARN=\"arn:aws:sns:region:account:topic-name\""
        exit 1
    fi
    
    # Validate SNS ARN format
    if [[ ! "$SNS_TOPIC_ARN" =~ ^arn:aws:sns:[^:]+:[^:]+:[^:]+$ ]]; then
        error "Invalid SNS Topic ARN format: $SNS_TOPIC_ARN"
        error "Expected format: arn:aws:sns:region:account-id:topic-name"
        exit 1
    fi
    
    # Check key file exists
    if [[ ! -f "ryanfill.pem" ]]; then
        error "Key file not found: ryanfill.pem"
        exit 1
    fi
    
    # Set proper permissions on key file
    chmod 400 ryanfill.pem
    
    success "Prerequisites check passed"
    success "SNS notifications will be sent to: $SNS_TOPIC_ARN"
}

# Verify SSM documents exist and are available
verify_ssm_documents() {
    log "Verifying SSM documents are available..."
    
    # Only check the main document (base install)
    if aws ssm describe-document --name "$SSM_MAIN_DOCUMENT" --region "$REGION" >/dev/null 2>&1; then
        success "SSM document found: $SSM_MAIN_DOCUMENT"
    else
        error "Missing SSM document: $SSM_MAIN_DOCUMENT"
        error "Please deploy SSM documents first using: scripts/deploy-ssm-documents.sh"
        exit 1
    fi
    
    success "Required SSM document is available"
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
    log "Launching EC2 instance..."
    
    # Create minimal user-data for SSM bootstrap
    local user_data='#!/bin/bash
# Minimal bootstrap for SSM-based Cockpit installation
dnf update -y
dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Wait for SSM agent to be ready
sleep 30

# Log readiness
echo "$(date): Instance ready for SSM automation" >> /var/log/ssm-bootstrap.log
'
    
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
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Cockpit-Outpost-Server},{Key=Purpose,Value=Cockpit-WebConsole},{Key=CockpitNotificationTopic,Value=$SNS_TOPIC_ARN},{Key=CockpitAutomation,Value=true}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [[ -z "$INSTANCE_ID" ]]; then
        error "Failed to launch instance"
        exit 1
    fi
    
    success "Instance launched: $INSTANCE_ID"
    echo "Instance ID: $INSTANCE_ID" > .last-instance-id
}

# Wait for instance to be fully ready with progressive status updates
wait_for_ssm_ready() {
    log "Waiting for Outpost instance to be fully ready (this may take 15-20 minutes)..."
    
    # Phase 1: Wait for instance to be running (usually 1-2 minutes)
    log "Phase 1/4: Waiting for instance state 'running'..."
    aws ec2 wait instance-running \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID"
    success "✅ Phase 1 complete: Instance is now running"
    
    # Phase 2: Wait for system status checks to pass (usually 5-15 minutes on Outpost)
    log "Phase 2/4: Waiting for system status checks (this takes longer on Outpost instances)..."
    local system_ready=false
    local attempts=0
    local max_system_attempts=30  # 15 minutes at 30-second intervals
    
    while [[ $system_ready == false ]] && [[ $attempts -lt $max_system_attempts ]]; do
        local system_status=$(aws ec2 describe-instance-status \
            --region "$REGION" \
            --instance-ids "$INSTANCE_ID" \
            --query 'InstanceStatuses[0].SystemStatus.Status' \
            --output text 2>/dev/null || echo "not-ready")
        
        local instance_status=$(aws ec2 describe-instance-status \
            --region "$REGION" \
            --instance-ids "$INSTANCE_ID" \
            --query 'InstanceStatuses[0].InstanceStatus.Status' \
            --output text 2>/dev/null || echo "not-ready")
        
        if [[ "$system_status" == "ok" && "$instance_status" == "ok" ]]; then
            system_ready=true
            success "✅ Phase 2 complete: System status checks passed"
        else
            ((attempts++))
            log "System status: $system_status, Instance status: $instance_status (attempt $attempts/$max_system_attempts)"
            sleep 30
        fi
    done
    
    if [[ $system_ready == false ]]; then
        warning "System status checks did not complete, but continuing with SSH connectivity test"
    fi
    
    # Phase 3: Wait for SSH connectivity (indicates instance is truly ready)
    log "Phase 3/4: Waiting for SSH connectivity..."
    local ssh_ready=false
    local ssh_attempts=0
    local max_ssh_attempts=20  # 10 minutes at 30-second intervals
    
    while [[ $ssh_ready == false ]] && [[ $ssh_attempts -lt $max_ssh_attempts ]]; do
        if ssh -i ryanfill.pem -o ConnectTimeout=5 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" "echo 'SSH ready'" >/dev/null 2>&1; then
            ssh_ready=true
            success "✅ Phase 3 complete: SSH connectivity established"
        else
            ((ssh_attempts++))
            log "SSH connectivity check $ssh_attempts/$max_ssh_attempts, retrying in 30 seconds..."
            sleep 30
        fi
    done
    
    if [[ $ssh_ready == false ]]; then
        warning "SSH connectivity not established, but continuing with SSM agent check"
    fi
    
    # Phase 4: Wait for SSM agent to be ready
    log "Phase 4/4: Waiting for SSM agent registration..."
    local ssm_ready=false
    local ssm_attempts=0
    local max_ssm_attempts=20  # 10 minutes at 30-second intervals
    
    while [[ $ssm_ready == false ]] && [[ $ssm_attempts -lt $max_ssm_attempts ]]; do
        if aws ssm describe-instance-information \
            --region "$REGION" \
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null | grep -q "Online"; then
            ssm_ready=true
            success "✅ Phase 4 complete: SSM agent is online and ready"
        else
            ((ssm_attempts++))
            log "SSM agent registration check $ssm_attempts/$max_ssm_attempts, retrying in 30 seconds..."
            sleep 30
        fi
    done
    
    if [[ $ssm_ready == false ]]; then
        error "SSM agent never came online after extended wait period"
        error "This may indicate network issues or Outpost connectivity problems"
        echo ""
        echo "Manual troubleshooting steps:"
        echo "1. Check SSH access: ssh -i ryanfill.pem rocky@$PUBLIC_IP"
        echo "2. Check SSM agent: sudo systemctl status amazon-ssm-agent"
        echo "3. Check bootstrap logs: sudo tail -f /var/log/user-data-bootstrap.log"
        exit 1
    fi
    
    success "🎉 All phases complete! Instance is fully ready for SSM automation"
}

# Get instance public IP and assign if needed
get_public_ip() {
    log "Getting instance public IP..."
    
    PUBLIC_IP=$(aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    if [[ "$PUBLIC_IP" == "None" ]] || [[ -z "$PUBLIC_IP" ]]; then
        warning "Instance has no public IP, attempting to assign Elastic IP..."
        
        # Try to find available EIP
        local eip_alloc=$(aws ec2 describe-addresses \
            --region "$REGION" \
            --query 'Addresses[?AssociationId==null].AllocationId' \
            --output text | head -1)
        
        if [[ -n "$eip_alloc" && "$eip_alloc" != "None" ]]; then
            log "Found available Elastic IP: $eip_alloc"
            aws ec2 associate-address \
                --region "$REGION" \
                --instance-id "$INSTANCE_ID" \
                --allocation-id "$eip_alloc" >/dev/null
            
            # Get the newly assigned public IP
            PUBLIC_IP=$(aws ec2 describe-instances \
                --region "$REGION" \
                --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' \
                --output text)
                
            success "Assigned Elastic IP: $PUBLIC_IP"
        else
            error "No available Elastic IPs found. Please ensure subnet auto-assigns public IPs or release an EIP."
            error "Alternatively, manually associate an Elastic IP after launch."
            exit 1
        fi
    else
        success "Instance already has public IP: $PUBLIC_IP"
    fi
    
    echo "Public IP: $PUBLIC_IP" >> .last-instance-id
}

# Execute SSM automation
execute_ssm_automation() {
    log "Starting SSM automation for Cockpit installation..."
    
    # Build parameters based on what's available
    local ssm_parameters="InstanceId=$INSTANCE_ID"
    
    # Add notification topic if provided
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        ssm_parameters="$ssm_parameters,NotificationTopic=$SNS_TOPIC_ARN"
    fi
    
    # Add continue on error setting
    ssm_parameters="$ssm_parameters,ContinueOnError=$CONTINUE_ON_ERROR"
    
    # Add automation assume role if provided
    local assume_role_param=""
    if [[ -n "$AUTOMATION_ASSUME_ROLE" ]]; then
        assume_role_param="--cli-input-json {\"AutomationAssumeRole\":\"$AUTOMATION_ASSUME_ROLE\"}"
        ssm_parameters="$ssm_parameters,AutomationAssumeRole=$AUTOMATION_ASSUME_ROLE"
    fi
    
    log "SSM Parameters: $ssm_parameters"
    
    EXECUTION_ID=$(aws ssm start-automation-execution \
        --region "$REGION" \
        --document-name "$SSM_MAIN_DOCUMENT" \
        --parameters "$ssm_parameters" \
        $assume_role_param \
        --query 'AutomationExecutionId' \
        --output text)
    
    if [[ -z "$EXECUTION_ID" ]]; then
        error "Failed to start SSM automation"
        exit 1
    fi
    
    success "SSM automation started: $EXECUTION_ID"
    echo "Execution ID: $EXECUTION_ID" >> .last-instance-id
    
    return 0
}

# Monitor SSM automation execution
monitor_ssm_execution() {
    log "Monitoring SSM automation execution..."
    
    local execution_complete=false
    local check_count=0
    local max_checks=60  # 30 minutes max
    
    while [[ $execution_complete == false ]] && [[ $check_count -lt $max_checks ]]; do
        ((check_count++))
        
        # Get execution status
        local execution_status=$(aws ssm describe-automation-executions \
            --region "$REGION" \
            --filters "Key=ExecutionId,Values=$EXECUTION_ID" \
            --query 'AutomationExecutions[0].AutomationExecutionStatus' \
            --output text 2>/dev/null || echo "Unknown")
        
        case "$execution_status" in
            "Success")
                execution_complete=true
                success "SSM automation completed successfully!"
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                execution_complete=true
                error "SSM automation failed with status: $execution_status"
                
                # Get failure details
                local failure_message=$(aws ssm describe-automation-executions \
                    --region "$REGION" \
                    --filters "Key=ExecutionId,Values=$EXECUTION_ID" \
                    --query 'AutomationExecutions[0].FailureMessage' \
                    --output text 2>/dev/null || echo "No failure message available")
                
                error "Failure details: $failure_message"
                return 1
                ;;
            "InProgress"|"Pending"|"Waiting")
                # Get current step information
                local current_step=$(aws ssm describe-automation-step-executions \
                    --region "$REGION" \
                    --automation-execution-id "$EXECUTION_ID" \
                    --query 'StepExecutions[?StepStatus==`InProgress`].StepName' \
                    --output text 2>/dev/null | head -1)
                
                if [[ -n "$current_step" && "$current_step" != "None" ]]; then
                    log "Progress: Executing step '$current_step' (check $check_count/$max_checks)"
                else
                    log "SSM automation in progress... (check $check_count/$max_checks)"
                fi
                ;;
            *)
                log "SSM automation status: $execution_status (check $check_count/$max_checks)"
                ;;
        esac
        
        if [[ $execution_complete == false ]]; then
            sleep 30  # Check every 30 seconds
        fi
    done
    
    if [[ $execution_complete == false ]]; then
        warning "SSM automation monitoring timed out after 30 minutes"
        log "Check execution status with: aws ssm describe-automation-executions --region $REGION --filters Key=ExecutionId,Values=$EXECUTION_ID"
        return 1
    fi
    
    return 0
}


# Verify Cockpit installation via SSM
verify_cockpit_via_ssm() {
    log "Verifying Cockpit installation via SSM..."
    
    # Run verification command via SSM
    local command_id=$(aws ssm send-command \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["systemctl is-active cockpit.socket", "curl -k -s --connect-timeout 5 https://localhost:9090/ >/dev/null && echo \"Cockpit web interface accessible\" || echo \"Cockpit web interface not accessible\""]' \
        --query 'Command.CommandId' \
        --output text)
    
    if [[ -z "$command_id" ]]; then
        warning "Failed to send verification command via SSM"
        return 1
    fi
    
    # Wait for command completion
    sleep 10
    
    # Get command results
    local verification_output=$(aws ssm get-command-invocation \
        --region "$REGION" \
        --command-id "$command_id" \
        --instance-id "$INSTANCE_ID" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "Failed to get verification results")
    
    if echo "$verification_output" | grep -q "active" && echo "$verification_output" | grep -q "accessible"; then
        success "Cockpit verification successful via SSM"
        return 0
    else
        warning "Cockpit verification failed via SSM"
        log "Verification output: $verification_output"
        return 1
    fi
}

# Open Cockpit in browser
open_cockpit() {
    local cockpit_url="https://$PUBLIC_IP:9090"
    
    success "Cockpit installation complete!"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "🚀 COCKPIT SERVER READY"
    echo "═══════════════════════════════════════════════════"
    echo "Instance ID:    $INSTANCE_ID"
    echo "Public IP:      $PUBLIC_IP"
    echo "Cockpit URL:    $cockpit_url"
    echo "SSH Access:     ssh -i ryanfill.pem rocky@$PUBLIC_IP"
    echo "SSM Execution:  $EXECUTION_ID"
    echo ""
    echo "Opening Cockpit in your browser..."
    echo "═══════════════════════════════════════════════════"
    
    # Open in browser (works on macOS)
    if command -v open &> /dev/null; then
        open "$cockpit_url"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$cockpit_url"
    else
        log "Please manually open: $cockpit_url"
    fi
}

# Cleanup function for interrupts
cleanup() {
    echo ""
    warning "Script interrupted"
    if [[ -n "$INSTANCE_ID" ]]; then
        echo "Instance ID: $INSTANCE_ID"
        echo "To terminate: aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCE_ID"
    fi
    if [[ -n "$EXECUTION_ID" ]]; then
        echo "SSM Execution: $EXECUTION_ID"
        echo "To stop: aws ssm stop-automation-execution --region $REGION --automation-execution-id $EXECUTION_ID"
    fi
    exit 1
}

# Set trap for cleanup
trap cleanup INT TERM

# Main execution
main() {
    echo "═══════════════════════════════════════════════════"
    echo "🏗️  AWS OUTPOST COCKPIT LAUNCHER - SSM ARCHITECTURE"
    echo "═══════════════════════════════════════════════════"
    echo "Outpost ID: $OUTPOST_ID"
    echo "Subnet ID:  $SUBNET_ID"
    echo "Instance:   $INSTANCE_TYPE"
    echo "SSM Docs:   $SSM_MAIN_DOCUMENT"
    echo "═══════════════════════════════════════════════════"
    echo ""
    
    check_prerequisites
    verify_ssm_documents
    get_latest_ami
    ensure_ssm_instance_profile
    launch_instance
    wait_for_ssm_ready
    get_public_ip
    
    # Provide immediate access information
    success "Instance launched successfully!"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "🚀 INSTANCE LAUNCHED - STARTING SSM AUTOMATION"
    echo "═══════════════════════════════════════════════════"
    echo "Instance ID: $INSTANCE_ID"
    echo "Public IP:   $PUBLIC_IP"
    echo "SSH Access:  ssh -i ryanfill.pem rocky@$PUBLIC_IP"
    echo ""
    echo "📧 You will receive email notifications for:"
    echo "   • Installation start"
    echo "   • Component progress" 
    echo "   • Installation completion"
    echo "   • Any errors or failures"
    echo ""
    echo "⏳ IMPORTANT: Outpost instances take longer to initialize"
    echo "   • Instance startup: ~15-20 minutes total"
    echo "   • Network connectivity establishment takes time"
    echo "   • This is normal behavior for Outpost infrastructure"
    echo ""
    echo "🔄 Starting SSM readiness check (with progress updates)..."
    echo "═══════════════════════════════════════════════════"
    
    # Execute SSM automation
    if execute_ssm_automation; then
        echo ""
        echo "📋 SSM Automation started successfully!"
        echo "   Execution ID: $EXECUTION_ID"
        echo ""
        
        # Ask user if they want to monitor execution progress
        read -p "Do you want to monitor SSM execution progress? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if monitor_ssm_execution; then
                # Verify installation
                if verify_cockpit_via_ssm; then
                    open_cockpit
                else
                    warning "Installation completed but verification failed"
                    echo "Cockpit URL: https://$PUBLIC_IP:9090"
                    echo "Manual verification: curl -k https://$PUBLIC_IP:9090/"
                fi
            else
                warning "SSM execution monitoring failed or timed out"
                echo ""
                echo "🔧 Individual component retry options:"
                echo "   System prep:    aws ssm send-command --document-name cockpit-system-prep --instance-ids $INSTANCE_ID"
                echo "   Core install:   aws ssm send-command --document-name cockpit-core-install --instance-ids $INSTANCE_ID" 
                echo "   Services setup: aws ssm send-command --document-name cockpit-services-setup --instance-ids $INSTANCE_ID"
                echo "   Extensions:     aws ssm send-command --document-name cockpit-extensions --instance-ids $INSTANCE_ID"
                echo "   User config:    aws ssm send-command --document-name cockpit-user-config --instance-ids $INSTANCE_ID"
                echo "   Finalization:   aws ssm send-command --document-name cockpit-finalize --instance-ids $INSTANCE_ID"
                echo ""
                echo "🔄 Or restart full automation:"
                echo "   aws ssm start-automation-execution --document-name cockpit-deploy-automation --parameters \"InstanceId=$INSTANCE_ID,NotificationTopic=$SNS_TOPIC_ARN\""
                echo ""
                echo "📊 Check execution status:"
                echo "   aws ssm describe-automation-executions --region $REGION --filters Key=ExecutionId,Values=$EXECUTION_ID"
            fi
        else
            echo "SSM automation is running in the background."
            echo "Check your email for progress notifications."
            echo "Cockpit URL: https://$PUBLIC_IP:9090"
            echo ""
            echo "📊 Monitor execution:"
            echo "   aws ssm describe-automation-executions --region $REGION --filters Key=ExecutionId,Values=$EXECUTION_ID"
        fi
    else
        error "Failed to start SSM automation"
        exit 1
    fi
}

# Run main function
main "$@"