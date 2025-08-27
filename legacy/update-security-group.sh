#!/bin/bash

# Security Group IP Update Script
# Checks if current public IP is allowed in the instance's security group
# Adds current IP if not present, never allows 0.0.0.0/0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
log() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Check if .env file exists and source it
if [ -f "../.env" ]; then
    source "../.env"
elif [ -f ".env" ]; then
    source ".env"
else
    log $RED "Error: .env file not found. Please ensure .env exists with REGION and other required variables."
    exit 1
fi

# Check required environment variables
if [ -z "$REGION" ]; then
    log $RED "Error: REGION not set in .env file"
    exit 1
fi

# Get current public IP
log $BLUE "Getting current public IP..."
CURRENT_IP=$(curl -s https://checkip.amazonaws.com/)

if [ -z "$CURRENT_IP" ]; then
    log $RED "Error: Could not determine current public IP"
    exit 1
fi

# Validate IP format
if ! [[ $CURRENT_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log $RED "Error: Invalid IP format: $CURRENT_IP"
    exit 1
fi

# Security check - never allow 0.0.0.0
if [ "$CURRENT_IP" = "0.0.0.0" ]; then
    log $RED "Error: Refusing to add 0.0.0.0/0 - this would allow all internet traffic"
    exit 1
fi

log $GREEN "Current public IP: $CURRENT_IP"

# Get instance ID from .last-instance-id or prompt user
INSTANCE_ID=""
if [ -f "../.last-instance-id" ]; then
    INSTANCE_ID=$(grep "Instance ID:" "../.last-instance-id" | cut -d' ' -f3)
    log $BLUE "Found instance ID from .last-instance-id: $INSTANCE_ID"
elif [ -f ".last-instance-id" ]; then
    INSTANCE_ID=$(grep "Instance ID:" ".last-instance-id" | cut -d' ' -f3)
    log $BLUE "Found instance ID from .last-instance-id: $INSTANCE_ID"
fi

# If no instance ID found, try to get from SECURITY_GROUP_ID in .env
if [ -z "$INSTANCE_ID" ] && [ -n "$SECURITY_GROUP_ID" ]; then
    log $YELLOW "No instance ID found, using SECURITY_GROUP_ID from .env: $SECURITY_GROUP_ID"
    SG_ID="$SECURITY_GROUP_ID"
else
    # Get security group from instance
    if [ -n "$INSTANCE_ID" ]; then
        log $BLUE "Getting security group for instance $INSTANCE_ID..."
        SG_ID=$(aws ec2 describe-instances \
            --region "$REGION" \
            --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
            --output text 2>/dev/null)
        
        if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
            log $RED "Error: Could not find security group for instance $INSTANCE_ID"
            exit 1
        fi
    else
        log $RED "Error: No instance ID found and no SECURITY_GROUP_ID in .env"
        log $YELLOW "Please ensure .last-instance-id exists or SECURITY_GROUP_ID is set in .env"
        exit 1
    fi
fi

log $GREEN "Using security group: $SG_ID"

# Check if current IP is already allowed on port 22 (SSH) and 9090 (Cockpit)
log $BLUE "Checking current security group rules..."

# Function to check if IP is allowed on a specific port
check_ip_allowed() {
    local port=$1
    local protocol=$2
    
    aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-ids "$SG_ID" \
        --query "SecurityGroups[0].IpPermissions[?FromPort==\`$port\` && ToPort==\`$port\` && IpProtocol==\`$protocol\`].IpRanges[?CidrIp==\`$CURRENT_IP/32\`]" \
        --output text
}

# Function to add IP to security group for a specific port
add_ip_to_sg() {
    local port=$1
    local protocol=$2
    local description=$3
    
    log $YELLOW "Adding $CURRENT_IP/32 to security group for port $port ($description)..."
    
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$SG_ID" \
        --protocol "$protocol" \
        --port "$port" \
        --cidr "$CURRENT_IP/32" \
        --source-group-name "Current IP Access - $(date '+%Y-%m-%d %H:%M')"
    
    if [ $? -eq 0 ]; then
        log $GREEN "✓ Successfully added $CURRENT_IP/32 for port $port"
    else
        log $RED "✗ Failed to add $CURRENT_IP/32 for port $port"
    fi
}

# Check and update SSH access (port 22)
SSH_ALLOWED=$(check_ip_allowed 22 tcp)
if [ -z "$SSH_ALLOWED" ]; then
    log $YELLOW "Current IP not allowed for SSH (port 22)"
    add_ip_to_sg 22 tcp "SSH"
else
    log $GREEN "✓ Current IP already allowed for SSH (port 22)"
fi

# Check and update Cockpit access (port 9090)
COCKPIT_ALLOWED=$(check_ip_allowed 9090 tcp)
if [ -z "$COCKPIT_ALLOWED" ]; then
    log $YELLOW "Current IP not allowed for Cockpit (port 9090)"
    add_ip_to_sg 9090 tcp "Cockpit"
else
    log $GREEN "✓ Current IP already allowed for Cockpit (port 9090)"
fi

# Display current security group rules for verification
log $BLUE "Current security group rules for SSH and Cockpit:"
aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` || FromPort==`9090`]' \
    --output table

# Security audit - check for 0.0.0.0/0 rules and warn
log $BLUE "Checking for overly permissive rules (0.0.0.0/0)..."
OPEN_RULES=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]' \
    --output text)

if [ -n "$OPEN_RULES" ] && [ "$OPEN_RULES" != "None" ]; then
    log $RED "⚠️  WARNING: Found rules allowing 0.0.0.0/0 (all internet traffic)"
    log $YELLOW "Consider restricting these rules for better security"
    aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-ids "$SG_ID" \
        --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]' \
        --output table
else
    log $GREEN "✓ No overly permissive 0.0.0.0/0 rules found"
fi

log $GREEN "Security group update complete!"
log $BLUE "Your current IP ($CURRENT_IP) should now have access to SSH and Cockpit"