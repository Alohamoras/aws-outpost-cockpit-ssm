#!/bin/bash
# Minimal user-data bootstrap for AWS Outpost instances
# Only handles network readiness and SSM agent setup
set -e

# Setup logging
exec > >(tee -a /var/log/user-data-bootstrap.log)
exec 2>&1
echo "=============================================="
echo "AWS OUTPOST MINIMAL BOOTSTRAP STARTED"
echo "Start Time: $(date)"
echo "=============================================="

# Outpost-optimized network timeout
MAX_NETWORK_ATTEMPTS=40
NETWORK_CHECK_INTERVAL=60

# Create SNS topic file (value substituted by launch script)
echo "{{SNS_TOPIC_ARN}}" > /tmp/sns-topic-arn.txt

# PHASE 1: NETWORK READINESS VALIDATION
echo "=== NETWORK READINESS VALIDATION ==="
echo "$(date): Waiting for Outpost network connectivity..."

network_ready=false
network_attempt=1

while [[ $network_ready == false ]] && [[ $network_attempt -le $MAX_NETWORK_ATTEMPTS ]]; do
    echo "🌐 Network attempt $network_attempt/$MAX_NETWORK_ATTEMPTS..."
    
    if curl -s --max-time 10 --connect-timeout 5 https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/repodata/repomd.xml >/dev/null 2>&1 && \
       curl -s --max-time 10 --connect-timeout 5 https://s3.amazonaws.com >/dev/null 2>&1; then
        echo "✅ NETWORK READY"
        network_ready=true
        break
    fi
    
    if [[ $network_attempt -eq $MAX_NETWORK_ATTEMPTS ]]; then
        echo "❌ NETWORK TIMEOUT after $MAX_NETWORK_ATTEMPTS attempts"
        exit 1
    fi
    
    sleep $NETWORK_CHECK_INTERVAL
    ((network_attempt++))
done

# PHASE 2: INSTANCE METADATA
echo "=== INSTANCE METADATA GATHERING ==="
INSTANCE_ID=$(curl -s --max-time 10 http://169.254.169.254/latest/meta-data/instance-id || echo "UNKNOWN")
REGION=$(curl -s --max-time 10 http://169.254.169.254/latest/meta-data/placement/region || echo "us-east-1")
echo "Instance ID: $INSTANCE_ID, Region: $REGION"

# PHASE 3: AWS CLI INSTALLATION (required for SSM)
echo "=== AWS CLI INSTALLATION ==="
if dnf install -y awscli || (dnf install -y python3-pip && pip3 install awscli --break-system-packages); then
    echo "✅ AWS CLI installed"
else
    echo "❌ AWS CLI installation failed"
    exit 1
fi

# PHASE 4: SSM AGENT INSTALLATION
echo "=== SSM AGENT INSTALLATION ==="
SSM_URL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm"
if dnf install -y "$SSM_URL"; then
    systemctl enable --now amazon-ssm-agent
    echo "✅ SSM Agent installed and started"
else
    echo "❌ SSM Agent installation failed"
    exit 1
fi

# PHASE 5: COMPLETION MARKERS
echo "=== BOOTSTRAP COMPLETION ==="
echo "$(date): Minimal bootstrap completed - ready for SSM execution" > /tmp/bootstrap-complete
echo "$INSTANCE_ID" > /tmp/instance-id
echo "$REGION" > /tmp/instance-region

echo "=============================================="
echo "✅ MINIMAL BOOTSTRAP SUCCESS - READY FOR SSM"
echo "Instance ID: $INSTANCE_ID"
echo "Network attempts: $network_attempt/$MAX_NETWORK_ATTEMPTS"
echo "Completion time: $(date)"
echo "=============================================="