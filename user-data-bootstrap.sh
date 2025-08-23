#!/bin/bash
# Rock-solid user-data bootstrap for AWS Outpost bare metal instances
# Optimized specifically for Outpost network timing and SSM requirements
set -e

# Setup comprehensive logging
exec > >(tee -a /var/log/user-data-bootstrap.log)
exec 2>&1
echo "=============================================="
echo "AWS OUTPOST BOOTSTRAP STARTED"
echo "Start Time: $(date)"
echo "=============================================="

# Get instance metadata early (for notifications)
echo "Gathering instance metadata..."
INSTANCE_ID=$(curl -s --max-time 10 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "UNKNOWN")
REGION=$(curl -s --max-time 10 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"

# Outpost-optimized timeouts (hardcoded for bare metal Outpost instances)
MAX_NETWORK_ATTEMPTS=40
NETWORK_CHECK_INTERVAL=60  # Check every 1 minute
SSM_REGISTRATION_WAIT=180

echo "Bootstrap configured for AWS Outpost bare metal instances"
echo "Network attempts: $MAX_NETWORK_ATTEMPTS, Check interval: ${NETWORK_CHECK_INTERVAL}s (40 minutes total), SSM wait: ${SSM_REGISTRATION_WAIT}s"

# SNS notification function (simple, no dependencies)
send_bootstrap_notification() {
    local status="$1"
    local message="$2"
    
    # Only send if we can determine SNS topic from environment or common locations
    local sns_topic=""
    
    # Try to get SNS topic from common environment locations
    if [[ -f /tmp/sns-topic-arn.txt ]]; then
        sns_topic=$(cat /tmp/sns-topic-arn.txt)
    elif [[ -n "$SNS_TOPIC_ARN" ]]; then
        sns_topic="$SNS_TOPIC_ARN"
    else
        # Try getting from SSM Parameter Store if AWS CLI works
        sns_topic=$(aws ssm get-parameter --name "/cockpit-deployment/sns-topic-arn" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "$sns_topic" && "$sns_topic" != "None" ]]; then
        aws sns publish \
            --region "$REGION" \
            --topic-arn "$sns_topic" \
            --subject "Bootstrap $status - $INSTANCE_ID" \
            --message "$message" 2>/dev/null || echo "SNS notification failed (expected during early bootstrap)"
    else
        echo "SNS notification skipped - no topic configured"
    fi
}

# PHASE 1: NETWORK READINESS (CRITICAL - MUST COME FIRST)
echo ""
echo "=== PHASE 1: NETWORK READINESS VALIDATION ==="
echo "$(date): Waiting for Outpost network connectivity before any package operations..."

# Progressive network readiness check with exponential backoff
network_ready=false
network_attempt=1

echo "Starting network readiness validation (max $MAX_NETWORK_ATTEMPTS attempts)..."

while [[ $network_ready == false ]] && [[ $network_attempt -le $MAX_NETWORK_ATTEMPTS ]]; do
    echo "🌐 Network readiness attempt $network_attempt/$MAX_NETWORK_ATTEMPTS..."
    
    # Test multiple endpoints to ensure robust connectivity
    if curl -s --max-time 10 --connect-timeout 5 https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/repodata/repomd.xml >/dev/null 2>&1 && \
       curl -s --max-time 10 --connect-timeout 5 https://s3.amazonaws.com >/dev/null 2>&1; then
        echo "✅ NETWORK READY: Repository and AWS S3 endpoints accessible"
        network_ready=true
        break
    fi
    
    if [[ $network_attempt -eq $MAX_NETWORK_ATTEMPTS ]]; then
        echo "❌ NETWORK TIMEOUT: Failed to establish connectivity after $MAX_NETWORK_ATTEMPTS attempts"
        echo "This may indicate Outpost network issues or extended initialization time"
        exit 1
    fi
    
    # Simple consistent interval for predictable timing
    echo "Network not ready, waiting $NETWORK_CHECK_INTERVAL seconds before retry..."
    sleep $NETWORK_CHECK_INTERVAL
    ((network_attempt++))
done

echo "$(date): Network readiness validation completed successfully"
send_bootstrap_notification "NETWORK_READY" "🌐 Network connectivity established on instance $INSTANCE_ID after $network_attempt attempts. Ready for package operations."

# PHASE 2: SYSTEM UPDATES (NOW SAFE TO DO NETWORK OPERATIONS)
echo ""
echo "=== PHASE 2: SYSTEM PACKAGE UPDATES ==="
echo "$(date): Network is ready, proceeding with system updates..."

# Enable retries for DNF operations now that network is confirmed working
retry_dnf() {
    local max_attempts=3
    local attempt=1
    local sleep_time=30
    
    while [ $attempt -le $max_attempts ]; do
        echo "DNF attempt $attempt/$max_attempts: $*"
        if dnf clean all >/dev/null 2>&1 && dnf "$@"; then
        echo "✅ DNF operation succeeded on attempt $attempt"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            echo "⚠️ DNF attempt $attempt failed, retrying in $sleep_time seconds..."
            sleep $sleep_time
        else
            echo "❌ DNF operation failed after $max_attempts attempts"
            return 1
        fi
        ((attempt++))
    done
}

# Update system packages
echo "Updating system packages..."
if ! retry_dnf update -y; then
    echo "❌ System package update failed"
    send_bootstrap_notification "FAILED" "System package update failed on instance $INSTANCE_ID during bootstrap"
    exit 1
fi

echo "✅ System packages updated successfully"

# PHASE 3: SSM AGENT INSTALLATION (NETWORK-DEPENDENT)
echo ""
echo "=== PHASE 3: AWS SSM AGENT INSTALLATION ==="
echo "$(date): Installing AWS SSM Agent..."

# Install SSM Agent from Amazon's direct URL (now safe since network is ready)
echo "Installing AWS SSM Agent from Amazon's repository..."
SSM_URL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
if ! retry_dnf install -y "$SSM_URL"; then
    echo "❌ SSM Agent installation failed"
    send_bootstrap_notification "FAILED" "SSM Agent installation failed on instance $INSTANCE_ID during bootstrap"
    exit 1
fi

echo "✅ SSM Agent installed successfully"

# Enable and start SSM Agent
echo "Enabling and starting SSM Agent service..."
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Verify SSM Agent is running
if systemctl is-active --quiet amazon-ssm-agent; then
    echo "✅ SSM Agent is running"
else
    echo "⚠️ SSM Agent service status unclear, continuing..."
fi

# PHASE 4: SSM AGENT REGISTRATION WAIT
echo ""
echo "=== PHASE 4: SSM AGENT REGISTRATION ==="
echo "$(date): Waiting for SSM Agent to register with AWS Systems Manager..."

# Extended wait for SSM registration (optimized for Outpost)
echo "Waiting $SSM_REGISTRATION_WAIT seconds for SSM agent registration..."
sleep $SSM_REGISTRATION_WAIT

# Test SSM connectivity if AWS CLI is available
if command -v aws >/dev/null 2>&1; then
    echo "Testing SSM connectivity..."
    if aws ssm describe-instance-information --region "$REGION" --filters "Name=InstanceIds,Values=$INSTANCE_ID" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
        echo "✅ SSM Agent registered and online"
    else
        echo "⚠️ SSM Agent registration status unclear (may still be in progress)"
    fi
else
    echo "ℹ️ AWS CLI not available for SSM connectivity test"
fi

# PHASE 5: COMPLETE COCKPIT INSTALLATION
echo ""
echo "=== PHASE 5: COMPLETE COCKPIT INSTALLATION ==="
echo "$(date): Starting complete Cockpit installation..."
send_bootstrap_notification "COCKPIT_STARTED" "🚀 Starting complete Cockpit installation on instance $INSTANCE_ID"

# Core Cockpit installation
echo "Installing core Cockpit packages..."
if ! retry_dnf install -y cockpit cockpit-system cockpit-ws cockpit-bridge cockpit-networkmanager cockpit-storaged cockpit-packagekit cockpit-sosreport; then
    echo "❌ Core Cockpit installation failed"
    send_bootstrap_notification "FAILED" "Core Cockpit installation failed on instance $INSTANCE_ID"
    exit 1
fi

# Extended services (compact installation)
echo "Installing extended services..."
retry_dnf groupinstall -y "Virtualization Host" || retry_dnf install -y qemu-kvm libvirt virt-install virt-manager || echo "Virtualization packages unavailable"
retry_dnf install -y cockpit-machines cockpit-podman podman buildah skopeo cockpit-pcp pcp pcp-system-tools || echo "Some extended packages unavailable"

# Third-party extensions (45Drives)
echo "Installing third-party extensions..."
cat > /etc/yum.repos.d/45drives.repo << 'EOF'
[45drives]
name=45Drives Repository  
baseurl=https://repo.45drives.com/rocky/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://repo.45drives.com/key/gpg.asc
EOF
rpm --import https://repo.45drives.com/key/gpg.asc 2>/dev/null || echo "GPG key import failed"
retry_dnf install -y cockpit-file-sharing cockpit-navigator cockpit-identities cockpit-sensors || echo "45Drives packages unavailable"

# Service configuration
echo "Configuring services..."
systemctl enable --now cockpit.socket NetworkManager
systemctl enable --now libvirtd pmcd pmlogger 2>/dev/null || echo "Some services unavailable"
if systemctl is-active --quiet firewalld; then firewall-cmd --permanent --add-service=cockpit && firewall-cmd --reload; fi

# User configuration
echo "Configuring users..."
if ! id admin >/dev/null 2>&1; then useradd -m -G wheel admin; fi
echo "admin:Cockpit123" | chpasswd; echo "rocky:Cockpit123" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel
usermod -a -G wheel,libvirt,kvm admin 2>/dev/null || echo "Group assignment warnings expected"
usermod -a -G wheel,libvirt,kvm rocky 2>/dev/null || echo "Group assignment warnings expected"

# Cockpit configuration
mkdir -p /etc/cockpit
cat > /etc/cockpit/cockpit.conf << 'EOF'
[WebService]
AllowUnencrypted = true
LoginTitle = AWS Outpost Cockpit Management Console
[Session]  
IdleTimeout = 60
EOF

# Final verification and restart
echo "Finalizing Cockpit installation..."
systemctl restart cockpit.socket && sleep 5
PUBLIC_IP=$(curl -s --max-time 10 http://169.254.169.254/latest/meta-data/public-ipv4 || echo "IP-NOT-AVAILABLE")

if systemctl is-active --quiet cockpit.socket; then
    echo "✅ Cockpit installation completed successfully"
    send_bootstrap_notification "COCKPIT_SUCCESS" "🎉 Cockpit deployment completed! Instance: $INSTANCE_ID, Access: https://$PUBLIC_IP:9090, Users: admin/rocky (password: Cockpit123)"
else
    echo "❌ Cockpit installation failed - service not active"
    send_bootstrap_notification "FAILED" "Cockpit installation failed - service not active on instance $INSTANCE_ID"
    exit 1
fi

# PHASE 6: BOOTSTRAP COMPLETION
echo ""
echo "=== PHASE 6: BOOTSTRAP COMPLETION ==="
echo "$(date): Finalizing bootstrap process..."

# Create status markers for launch script
echo "$(date): Bootstrap and Cockpit installation completed successfully" > /tmp/bootstrap-complete
echo "$INSTANCE_ID" > /tmp/instance-id
echo "$REGION" > /tmp/instance-region
echo "$PUBLIC_IP" > /tmp/instance-public-ip

# Final notification
echo "$(date): Instance $INSTANCE_ID bootstrap and Cockpit installation completed successfully"
send_bootstrap_notification "SUCCESS" "🚀 Complete deployment finished on instance $INSTANCE_ID! Cockpit accessible at https://$PUBLIC_IP:9090"

echo ""
echo "=============================================="
echo "🎉 COMPLETE COCKPIT DEPLOYMENT SUCCESS!"
echo "=============================================="
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "Cockpit URL: https://$PUBLIC_IP:9090"
echo "Users: admin/rocky (Password: Cockpit123)"
echo "Completion Time: $(date)"
echo "Network Attempts: $network_attempt/$MAX_NETWORK_ATTEMPTS"
echo "=============================================="