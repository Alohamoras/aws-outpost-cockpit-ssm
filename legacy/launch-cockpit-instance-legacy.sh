#!/bin/bash

# AWS Outpost Cockpit Instance Launch Script - Self-Contained User-Data
# Launches EC2 instance with complete Cockpit installation via user-data

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


# SSM_MAIN_DOCUMENT removed - not needed

# SNS Topic ARN removed from legacy version

# Storage configuration (optional)
CONFIGURE_STORAGE="${CONFIGURE_STORAGE:-false}"

# These variables are no longer needed for self-contained user-data approach
# CONTINUE_ON_ERROR and AUTOMATION_ASSUME_ROLE removed

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
    
    # Check key file exists
    KEY_FILE="${KEY_NAME}.pem"
    if [[ ! -f "$KEY_FILE" ]]; then
        error "SSH key file not found: $KEY_FILE"
        error "Please copy your SSH private key to this directory:"
        error "  cp /path/to/your-private-key.pem $KEY_FILE"
        error "  chmod 400 $KEY_FILE"
        error ""
        error "The key name is based on your KEY_NAME environment variable: $KEY_NAME"
        error "Make sure this matches your EC2 key pair name in AWS."
        exit 1
    fi
    
    # Set proper permissions on key file
    chmod 400 "$KEY_FILE"
    
    success "Prerequisites check passed"
}

# No SSM document verification needed - everything in user-data
# verify_ssm_documents() removed - not needed

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
    
    # Load user-data from legacy bootstrap script file
    if [[ ! -f "legacy/user-data-bootstrap-legacy.sh" ]]; then
        error "legacy/user-data-bootstrap-legacy.sh file not found"
        exit 1
    fi
    
    # Load user-data without SNS substitution
    local user_data="$(cat legacy/user-data-bootstrap-legacy.sh)"
    
    log "User-data prepared for bootstrap (legacy version without SNS)"
    
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
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Cockpit-Outpost-Server},{Key=Purpose,Value=Cockpit-WebConsole},{Key=CockpitAutomation,Value=true}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [[ -z "$INSTANCE_ID" ]]; then
        error "Failed to launch instance"
        exit 1
    fi
    
    success "Instance launched: $INSTANCE_ID"
    echo "Instance ID: $INSTANCE_ID" > .last-instance-id
}

# New streamlined functions for better user experience

# Wait for basic instance readiness (running state)
wait_for_instance_ready() {
    log "Waiting for instance to reach 'running' state..."
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
    success "✅ Instance is now running"
}

# Verify public IP is assigned and accessible
verify_public_ip() {
    log "Verifying public IP assignment..."
    
    PUBLIC_IP=$(aws ec2 describe-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null)
    
    if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
        error "No public IP assigned to instance"
        log "Attempting to assign Elastic IP..."
        
        # Try to find an available Elastic IP
        local available_eip=$(aws ec2 describe-addresses \
            --region "$REGION" \
            --query 'Addresses[?InstanceId==null && NetworkInterfaceId==null] | [0].AllocationId' \
            --output text 2>/dev/null)
        
        if [[ -n "$available_eip" && "$available_eip" != "None" ]]; then
            log "Found available Elastic IP, associating..."
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
        
        if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
            error "Failed to assign public IP. Instance cannot be accessed for Cockpit."
            exit 1
        fi
    fi
    
    success "✅ Public IP assigned: $PUBLIC_IP"
    echo "Instance ID: $INSTANCE_ID" > .last-instance-id
    echo "Public IP: $PUBLIC_IP" >> .last-instance-id
}

# Verify security group allows SSH access from current IP
verify_ssh_access() {
    log "Verifying security group allows SSH access..."
    
    # Get current public IP
    local my_ip=$(curl -s https://checkip.amazonaws.com || curl -s https://ipinfo.io/ip)
    if [[ -z "$my_ip" ]]; then
        warning "Could not determine your current public IP"
        warning "Please ensure security group $SECURITY_GROUP_ID allows SSH (port 22) from your IP"
        return 0
    fi
    
    # Check if security group allows SSH from this IP
    local ssh_allowed=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-ids "$SECURITY_GROUP_ID" \
        --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\` && ToPort==\`22\`].IpRanges[?contains(CidrIp, '$my_ip') || CidrIp=='0.0.0.0/0']" \
        --output text 2>/dev/null)
    
    if [[ -z "$ssh_allowed" ]]; then
        warning "Security group may not allow SSH access from your IP ($my_ip)"
        warning "If SSH connectivity fails, please add rule: SSH (port 22) from $my_ip/32"
    else
        success "✅ Security group allows SSH access from your IP ($my_ip)"
    fi
}

# Wait for SSH connectivity with extended timeout
wait_for_ssh_connectivity() {
    log "Waiting for SSH connectivity (up to 60 minutes for Outpost instances)..."
    
    local ssh_ready=false
    local attempts=0
    local max_attempts=120  # 60 minutes at 30-second intervals
    
    while [[ $ssh_ready == false ]] && [[ $attempts -lt $max_attempts ]]; do
        ((attempts++))
        
        if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" "echo 'SSH OK'" >/dev/null 2>&1; then
            ssh_ready=true
            success "✅ SSH connectivity established after $attempts attempts ($((attempts * 30 / 60)) minutes)"
        else
            log "SSH attempt $attempts/$max_attempts failed, retrying in 30 seconds..."
            sleep 30
        fi
    done
    
    if [[ $ssh_ready == false ]]; then
        error "SSH connectivity failed after 60 minutes"
        error "Please check:"
        error "1. Security group allows SSH (port 22) from your IP"
        error "2. Key pair '$KEY_NAME' is correct"
        error "3. Instance is fully booted"
        exit 1
    fi
}

# Monitor bootstrap progress via real-time log tailing
monitor_bootstrap_progress() {
    log "🔄 Monitoring bootstrap progress in real-time..."
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "📋 BOOTSTRAP LOG (press Ctrl+C to stop monitoring)"
    echo "═══════════════════════════════════════════════════"
    
    # Tail the bootstrap log until completion
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
        "sudo tail -f /var/log/user-data-bootstrap.log" | \
        while IFS= read -r line; do
            echo "$line"
            # Stop when we see the completion message
            if echo "$line" | grep -q "COMPLETE COCKPIT DEPLOYMENT SUCCESS"; then
                break
            fi
        done
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    success "🎉 Bootstrap monitoring completed!"
    echo "═══════════════════════════════════════════════════"
}

# Configure storage drives (optional post-bootstrap step)
configure_storage_drives() {
    # Check if storage configuration is enabled
    if [[ "${CONFIGURE_STORAGE:-false}" != "true" ]]; then
        log "Storage configuration disabled (CONFIGURE_STORAGE=false)"
        return 0
    fi
    
    log "🔧 Starting optional storage configuration..."
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "💾 STORAGE CONFIGURATION (RAID + LVM)"
    echo "═══════════════════════════════════════════════════"
    
    # Transfer storage configuration script to instance
    log "Transferring storage configuration script..."
    if ! scp -i "$KEY_FILE" -o StrictHostKeyChecking=no configure-storage.sh rocky@"$PUBLIC_IP":/tmp/; then
        warning "Failed to transfer storage script - skipping storage configuration"
        return 1
    fi
    
    # Execute storage configuration script with real-time output
    log "Executing storage configuration on instance..."
    echo ""
    
    if ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
        "sudo chmod +x /tmp/configure-storage.sh && sudo /tmp/configure-storage.sh" | \
        while IFS= read -r line; do
            echo "$line"
            # Stop if we see completion message
            if echo "$line" | grep -q "Storage configuration completed successfully"; then
                break
            fi
        done; then
        
        echo ""
        echo "═══════════════════════════════════════════════════"
        success "✅ Storage configuration completed successfully!"
        echo "═══════════════════════════════════════════════════"
        
        # Restart services to recognize new storage
        log "Restarting Cockpit services to recognize new storage..."
        ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" \
            "sudo systemctl restart cockpit.socket && sudo systemctl restart libvirtd && sudo systemctl restart podman" || \
            warning "Some services may need manual restart"
        
        return 0
    else
        echo ""
        echo "═══════════════════════════════════════════════════"
        warning "⚠️ Storage configuration encountered issues"
        echo "═══════════════════════════════════════════════════"
        log "Storage configuration failed or had warnings"
        log "Check storage manually: ssh -i $KEY_FILE rocky@$PUBLIC_IP 'sudo lsblk'"
        return 1
    fi
}

# OLD FUNCTIONS (will be removed)
# Wait for instance to be fully ready and bootstrap to complete
wait_for_bootstrap_ready() {
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
    local max_ssh_attempts=60  # 30 minutes at 30-second intervals
    
    while [[ $ssh_ready == false ]] && [[ $ssh_attempts -lt $max_ssh_attempts ]]; do
        if ssh -i "$KEY_FILE" -o ConnectTimeout=5 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" "echo 'SSH ready'" >/dev/null 2>&1; then
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
        echo "1. Check SSH access: ssh -i $KEY_FILE rocky@$PUBLIC_IP"
        echo "2. Check SSM agent: sudo systemctl status amazon-ssm-agent"
        echo "3. Check bootstrap logs: sudo tail -f /var/log/user-data-bootstrap.log"
        exit 1
    fi
    
    success "🎉 All phases complete! Instance is ready, checking bootstrap completion..."
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

# Wait for bootstrap completion
wait_for_bootstrap_completion() {
    log "Waiting for user-data bootstrap to complete Cockpit installation..."
    
    local bootstrap_complete=false
    local check_count=0
    local max_checks=120  # 60 minutes max for complete installation
    
    while [[ $bootstrap_complete == false ]] && [[ $check_count -lt $max_checks ]]; do
        ((check_count++))
        
        # Check if bootstrap completion marker exists via SSH
        if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" "test -f /tmp/bootstrap-complete" >/dev/null 2>&1; then
            bootstrap_complete=true
            success "Bootstrap and Cockpit installation completed successfully!"
        else
            log "Bootstrap in progress... (check $check_count/$max_checks)"
            sleep 30  # Check every 30 seconds
        fi
    done
    
    if [[ $bootstrap_complete == false ]]; then
        warning "Bootstrap completion check timed out after 60 minutes"
        log "Check bootstrap status manually: ssh -i $KEY_FILE rocky@$PUBLIC_IP 'sudo tail -f /var/log/user-data-bootstrap.log'"
        return 1
    fi
    
    return 0
}

# No SSM monitoring needed - bootstrap handles everything
# monitor_ssm_execution() removed - not needed


# Verify Cockpit installation via SSH
verify_cockpit_installation() {
    log "Verifying Cockpit installation..."
    
    # Check if Cockpit is running via SSH
    local cockpit_status=$(ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o StrictHostKeyChecking=no rocky@"$PUBLIC_IP" "systemctl is-active cockpit.socket" 2>/dev/null || echo "inactive")
    
    if [[ "$cockpit_status" == "active" ]]; then
        success "Cockpit service is active"
        
        # Test web interface accessibility
        if curl -k -s --connect-timeout 10 "https://$PUBLIC_IP:9090/" >/dev/null 2>&1; then
            success "Cockpit web interface is accessible"
            return 0
        else
            warning "Cockpit service active but web interface not accessible"
            return 1
        fi
    else
        warning "Cockpit service not active: $cockpit_status"
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
    echo "SSH Access:     ssh -i $KEY_FILE rocky@$PUBLIC_IP"
    echo "Login:          admin/rocky (password: Cockpit123)"
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
        echo "Check bootstrap: ssh -i $KEY_FILE rocky@$PUBLIC_IP 'sudo tail -f /var/log/user-data-bootstrap.log'"
    fi
    exit 1
}

# Set trap for cleanup
trap cleanup INT TERM

# Main execution
main() {
    echo "═══════════════════════════════════════════════════"
    echo "🏗️  AWS OUTPOST COCKPIT LAUNCHER - SELF-CONTAINED"
    echo "═══════════════════════════════════════════════════"
    echo "Outpost ID: $OUTPOST_ID"
    echo "Subnet ID:  $SUBNET_ID"
    echo "Instance:   $INSTANCE_TYPE"
    echo "Method:     User-Data Bootstrap"
    if [[ "$CONFIGURE_STORAGE" == "true" ]]; then
        echo "Storage:    Auto-configure RAID + LVM"
    else
        echo "Storage:    Manual (set CONFIGURE_STORAGE=true to enable)"
    fi
    echo "═══════════════════════════════════════════════════"
    echo ""
    
    check_prerequisites
    get_latest_ami
    ensure_ssm_instance_profile
    launch_instance
    wait_for_instance_ready
    verify_public_ip
    verify_ssh_access
    wait_for_ssh_connectivity
    monitor_bootstrap_progress
    configure_storage_drives
    
    # Final summary after monitoring completes
    success "🎉 Cockpit deployment completed successfully!"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "🚀 COCKPIT IS NOW READY"
    echo "═══════════════════════════════════════════════════"
    echo "Instance ID: $INSTANCE_ID"
    echo "Public IP:   $PUBLIC_IP"
    echo "Cockpit URL: https://$PUBLIC_IP:9090"
    echo "SSH Access:  ssh -i $KEY_FILE rocky@$PUBLIC_IP"
    echo ""
    echo "👤 Login credentials:"
    echo "   Username: admin or rocky"
    echo "   Password: Cockpit123"
    echo "═══════════════════════════════════════════════════"
    
    # Try to open Cockpit automatically
    open_cockpit
}

# Run main function
main "$@"