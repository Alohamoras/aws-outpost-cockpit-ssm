#!/bin/bash
# Minimal user-data bootstrap for SSM-based Cockpit installation
set -e

# Setup logging
exec > >(tee -a /var/log/user-data-bootstrap.log)
exec 2>&1
echo "Starting SSM bootstrap at $(date)"

# Update system and install basic packages
dnf update -y

# Install and start SSM agent
dnf install -y amazon-ssm-agent
systemctl enable --now amazon-ssm-agent

# Network validation with exponential backoff (max 30 min)
echo "Validating network connectivity..."
for i in {1..20}; do
    echo "Network check attempt $i/20..."
    if curl -s --max-time 10 https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/repodata/repomd.xml >/dev/null; then
        echo "Network connectivity confirmed"
        break
    fi
    if [ $i -eq 20 ]; then
        echo "Network timeout after 30 minutes"
        exit 1
    fi
    echo "Network not ready, waiting $((60 * i)) seconds..."
    sleep $((60 * i))
done

# Wait for SSM agent to be ready
echo "Waiting for SSM agent to register..."
sleep 30

# Log readiness for SSM automation (triggered externally by launch script)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "$(date): Instance $INSTANCE_ID ready for SSM automation"
echo "Bootstrap completed at $(date)"