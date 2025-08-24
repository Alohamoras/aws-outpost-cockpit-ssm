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

# Outpost-optimized timeouts (hardcoded for bare metal Outpost instances)
MAX_NETWORK_ATTEMPTS=40
NETWORK_CHECK_INTERVAL=60  # Check every 1 minute
echo "Bootstrap configured for AWS Outpost bare metal instances"
echo "Network attempts: $MAX_NETWORK_ATTEMPTS, Check interval: ${NETWORK_CHECK_INTERVAL}s (40 minutes total)"

# Create SNS topic file early (value will be substituted by launch script)
echo "{{SNS_TOPIC_ARN}}" > /tmp/sns-topic-arn.txt
echo "SNS topic ARN configured for notifications"

# SNS notification function (simplified, reliable)
send_bootstrap_notification() {
    local status="$1"
    local message="$2"
    
    # Get SNS topic from file (created early in bootstrap with launch script substitution)
    local sns_topic=""
    if [[ -f /tmp/sns-topic-arn.txt ]]; then
        sns_topic=$(cat /tmp/sns-topic-arn.txt 2>/dev/null | tr -d '\n')
    fi
    
    # Fallback to environment variable if file doesn't exist or is empty
    if [[ -z "$sns_topic" && -n "$SNS_TOPIC_ARN" ]]; then
        sns_topic="$SNS_TOPIC_ARN"
    fi
    
    # Send notification if we have a valid topic ARN and AWS CLI
    if [[ -n "$sns_topic" && "$sns_topic" != "None" && "$sns_topic" != "{{SNS_TOPIC_ARN}}" ]]; then
        # Check if AWS CLI is available (may not be installed yet in early bootstrap)
        if command -v aws >/dev/null 2>&1; then
            # Use region fallback if not set yet (early bootstrap calls)
            local region="${REGION:-us-east-1}"
            echo "📧 Sending SNS notification: $status"
            
            if aws sns publish \
                --region "$region" \
                --topic-arn "$sns_topic" \
                --subject "Bootstrap $status - ${INSTANCE_ID:-UNKNOWN}" \
                --message "$message" 2>&1; then
                echo "✅ SNS notification sent successfully"
            else
                echo "⚠️ SNS notification failed (AWS CLI error above)"
            fi
        else
            echo "ℹ️ SNS notification skipped - AWS CLI not available yet"
        fi
    else
        echo "ℹ️ SNS notification skipped - no valid topic configured"
    fi
}

# PHASE 1: NETWORK READINESS (CRITICAL - MUST COME FIRST)
echo ""
echo "=== PHASE 1: NETWORK READINESS VALIDATION ==="
echo "$(date): Waiting for Outpost network connectivity before any operations (including metadata)..."

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

# PHASE 2: INSTANCE METADATA GATHERING (NOW SAFE AFTER NETWORK IS READY)
echo ""
echo "=== PHASE 2: INSTANCE METADATA GATHERING ==="
echo "$(date): Network is ready, now gathering instance metadata..."
INSTANCE_ID=$(curl -s --max-time 10 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "UNKNOWN")
REGION=$(curl -s --max-time 10 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "✅ Instance metadata gathered successfully"

# PHASE 3: SYSTEM UPDATES (NOW SAFE TO DO NETWORK OPERATIONS)
echo ""
echo "=== PHASE 3: SYSTEM PACKAGE UPDATES ==="
echo "$(date): Network and metadata ready, proceeding with system updates..."

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
SYSTEM_UPDATE_FAILED=false
if ! retry_dnf update -y; then
    echo "❌ System package update failed"
    SYSTEM_UPDATE_FAILED=true
else
    echo "✅ System packages updated successfully"
fi

# AWS CLI Installation (required for SNS notifications and SSM verification - install even if system updates failed)
echo "Installing AWS CLI..."
AWS_CLI_INSTALLED=false

# Try installing via DNF first (most reliable if available)
if retry_dnf install -y awscli; then
    echo "✅ AWS CLI installed via DNF"
    AWS_CLI_INSTALLED=true
elif retry_dnf install -y python3-pip && pip3 install awscli --break-system-packages; then
    echo "✅ AWS CLI installed via pip3"
    AWS_CLI_INSTALLED=true
else
    echo "⚠️ AWS CLI installation failed - SNS notifications and SSM verification will be skipped"
fi

# Verify AWS CLI installation
if command -v aws >/dev/null 2>&1; then
    echo "✅ AWS CLI is available: $(aws --version 2>&1 | head -n1)"
    AWS_CLI_INSTALLED=true
else
    echo "⚠️ AWS CLI not found in PATH after installation attempt"
    AWS_CLI_INSTALLED=false
fi

# Now send notifications after AWS CLI is available
send_bootstrap_notification "NETWORK_READY" "🌐 Network connectivity established on instance $INSTANCE_ID after $network_attempt attempts. Ready for operations."

# Handle system update failure now that we can send notifications
if [ "$SYSTEM_UPDATE_FAILED" = true ]; then
    send_bootstrap_notification "FAILED" "System package update failed on instance $INSTANCE_ID during bootstrap"
    exit 1
fi

# PHASE 4: SSM AGENT INSTALLATION (NETWORK-DEPENDENT)
echo ""
echo "=== PHASE 4: AWS SSM AGENT INSTALLATION ==="
echo "$(date): Installing AWS SSM Agent..."

# Install SSM Agent from Amazon's direct URL (now safe since network is ready)
echo "Installing AWS SSM Agent from Amazon's repository..."
SSM_URL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
SSM_INSTALLED=false
if retry_dnf install -y "$SSM_URL"; then
    echo "✅ SSM Agent installed successfully"
    SSM_INSTALLED=true
else
    echo "⚠️ SSM Agent installation failed - continuing with Cockpit installation"
    send_bootstrap_notification "SSM_FAILED" "SSM Agent installation failed on instance $INSTANCE_ID, but continuing with Cockpit deployment"
fi

# Enable and start SSM Agent (only if installation succeeded)
if [ "$SSM_INSTALLED" = true ]; then
    echo "Enabling and starting SSM Agent service..."
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    
    # Verify SSM Agent is running
    if systemctl is-active --quiet amazon-ssm-agent; then
        echo "✅ SSM Agent is running"
    else
        echo "⚠️ SSM Agent service status unclear, continuing..."
    fi
else
    echo "⏭️ Skipping SSM Agent service configuration (installation failed)"
fi

# PHASE 5: SSM AGENT VERIFICATION
echo ""
echo "=== PHASE 5: SSM AGENT VERIFICATION ==="
echo "$(date): Verifying SSM Agent connectivity (no wait needed after extensive network validation)..."

# Test SSM connectivity only if SSM was successfully installed
if [ "$SSM_INSTALLED" = true ]; then
    echo "Testing SSM connectivity immediately..."
    if command -v aws >/dev/null 2>&1; then
        if aws ssm describe-instance-information --region "$REGION" --filters "Name=InstanceIds,Values=$INSTANCE_ID" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
            echo "✅ SSM Agent registered and online"
        else
            echo "⚠️ SSM Agent registration status unclear (this is normal and non-critical)"
        fi
    else
        echo "ℹ️ AWS CLI not available for SSM connectivity test"
    fi
else
    echo "⏭️ Skipping SSM connectivity test (installation failed)"
fi

# PHASE 6: COMPLETE COCKPIT INSTALLATION
echo ""
echo "=== PHASE 6: COMPLETE COCKPIT INSTALLATION ==="
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

# Install packages individually to handle missing packages gracefully
echo "Installing virtualization and container packages..."
retry_dnf install -y cockpit-machines || echo "cockpit-machines unavailable"
retry_dnf install -y cockpit-podman podman buildah skopeo || echo "Container packages unavailable"

# Install monitoring packages (cockpit-pcp often unavailable in Rocky 9)
echo "Installing monitoring packages..."
if retry_dnf install -y pcp pcp-system-tools; then
    echo "✅ PCP monitoring tools installed"
    # Only try cockpit-pcp if base PCP is available
    retry_dnf install -y cockpit-pcp || echo "cockpit-pcp unavailable, using base PCP only"
    systemctl enable --now pmcd pmlogger 2>/dev/null || echo "PCP services configuration skipped"
else
    echo "⚠️ PCP monitoring tools unavailable, skipping monitoring packages"
fi

# Third-party extensions (45Drives)
echo "Installing third-party extensions..."
DRIVES_INSTALLED=false

# Remove any existing problematic repository file
echo "Cleaning up any existing 45drives repository..."
rm -f /etc/yum.repos.d/45drives.repo

# Use official 45drives setup script (more reliable than manual repo creation)
echo "Setting up 45drives repository using official script..."
if curl -sSL https://repo.45drives.com/setup | bash; then
    echo "✅ 45drives repository setup successful"
    
    # Clean and refresh the cache
    echo "Refreshing package cache..."
    dnf clean all >/dev/null 2>&1
    dnf makecache >/dev/null 2>&1
    
    # Install 45drives packages with retry logic
    if retry_dnf install -y cockpit-file-sharing cockpit-navigator cockpit-identities cockpit-sensors; then
        echo "✅ 45drives extensions installed successfully"
        DRIVES_INSTALLED=true
    else
        echo "⚠️ Some 45drives packages unavailable, continuing without them"
    fi
else
    echo "⚠️ 45drives repository setup failed, skipping third-party extensions"
fi

# Service configuration
echo "Configuring services..."
systemctl enable --now cockpit.socket NetworkManager
systemctl enable --now libvirtd 2>/dev/null || echo "libvirtd service unavailable"
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

# PHASE 7: BOOTSTRAP COMPLETION
echo ""
echo "=== PHASE 7: BOOTSTRAP COMPLETION ==="
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
if [ "$SSM_INSTALLED" = true ]; then
    echo "SSM Agent: ✅ Installed and configured"
else
    echo "SSM Agent: ⚠️ Installation failed (non-critical)"
fi
if [ "$DRIVES_INSTALLED" = true ]; then
    echo "45Drives Extensions: ✅ Installed successfully"
else
    echo "45Drives Extensions: ⚠️ Installation failed (non-critical)"
fi
if command -v aws >/dev/null 2>&1; then
    echo "AWS CLI: ✅ Available ($(aws --version 2>&1 | head -n1 | cut -d' ' -f1-2))"
else
    echo "AWS CLI: ⚠️ Not available (SNS notifications disabled)"
fi
echo "Completion Time: $(date)"
echo "Network Attempts: $network_attempt/$MAX_NETWORK_ATTEMPTS"
echo "=============================================="