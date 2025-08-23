# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project automates the deployment of Cockpit web console on AWS Outpost instances using a self-contained user-data approach. It provides infrastructure-as-code for launching EC2 instances with complete Cockpit installation during bootstrap.

## Architecture

The system uses a streamlined self-contained architecture:

### Current Self-Contained Architecture
- **Main launcher**: `launch-cockpit-instance.sh` - Orchestrates the entire deployment
- **Complete bootstrap**: `user-data-bootstrap.sh` - Full Cockpit installation during instance launch
- **Instance management**: `legacy/manage-instances.sh` - Operations utilities

### Key Components
- EC2 instance launch with Rocky Linux 9
- IAM role and instance profile management for basic functionality
- SNS notifications for installation progress
- Elastic IP assignment and network configuration
- Complete Cockpit installation via user-data script (no external dependencies)

## Environment Configuration

### Required Setup
1. Copy environment template: `cp .env.example .env`
2. Configure required values in `.env`:
   - `OUTPOST_ID` - Your AWS Outpost ID
   - `SUBNET_ID` - Target subnet for instances
   - `SECURITY_GROUP_ID` - Security group allowing port 9090
   - `KEY_NAME` - EC2 key pair name
   - `SNS_TOPIC_ARN` - SNS topic for notifications (required)
   - `REGION` - AWS region (default: us-east-1)

### SSH Key
- The project expects `${KEY_NAME}.pem` SSH private key in the root directory (defaults to `ryanfill.pem`)
- Key name is configurable via the `KEY_NAME` environment variable in `.env`
- Key permissions are automatically set to 400 during execution

## Common Commands

### Launch New Instance
```bash
./launch-cockpit-instance.sh
```
The launcher will:
- Verify prerequisites (AWS CLI, SNS topic, SSH key)
- Find latest Rocky Linux 9 AMI
- Create IAM roles if needed
- Launch instance with complete Cockpit installation via user-data
- Monitor bootstrap progress via console logs (no SSH required)
- Provide access URLs and login credentials

### Instance Management
```bash
# Check instance status
./legacy/manage-instances.sh status

# SSH into instance
./legacy/manage-instances.sh ssh

# Monitor installation logs
./legacy/manage-instances.sh logs

# Open Cockpit web interface
./legacy/manage-instances.sh cockpit

# Check service health
./legacy/manage-instances.sh services

# Terminate instance (with confirmation)
./legacy/manage-instances.sh terminate
```

### Bootstrap Troubleshooting
The launcher now monitors bootstrap progress via console logs automatically. For manual troubleshooting:
```bash
# Monitor console logs (primary method - no SSH required)
aws ec2 get-console-output --region $REGION --instance-id $INSTANCE_ID

# Test Cockpit web interface accessibility
curl -k https://$PUBLIC_IP:9090/

# Optional: SSH-based troubleshooting (if SSH access is available)
ssh -i ${KEY_NAME}.pem rocky@$PUBLIC_IP 'sudo tail -f /var/log/user-data-bootstrap.log'
ssh -i ${KEY_NAME}.pem rocky@$PUBLIC_IP 'systemctl status cockpit.socket'
```

## File Structure

```
.
├── launch-cockpit-instance.sh    # Main launcher (self-contained)
├── user-data-bootstrap.sh        # Complete Cockpit installation bootstrap
├── .env.example                  # Environment template
├── .env                         # Local configuration (gitignored)
├── ${KEY_NAME}.pem              # SSH private key (configurable via KEY_NAME)
├── .last-instance-id            # Tracks most recent instance
└── legacy/                      # Legacy scripts directory
    ├── README.md                # Legacy documentation
    └── manage-instances.sh      # Instance operations utility
```

## Development Notes

### Instance State Tracking
- Instance details are stored in `.last-instance-id` after launch
- Contains instance ID, public IP, and bootstrap status for management operations

### Networking
- Instances require public IP access for Cockpit web interface
- Script automatically assigns available Elastic IP if needed
- Cockpit accessible on port 9090 (HTTPS)

### User Accounts
- Default users: `admin` and `rocky` (both with password: `Cockpit123`)
- Both users have sudo access via wheel group membership
- Users configured for Cockpit access with virtualization and container permissions

### Error Handling
- All scripts use `set -e` for fail-fast behavior
- Comprehensive logging with color-coded output
- SNS notifications for bootstrap and installation progress
- Robust retry mechanisms for network operations and package installations

### Bootstrap Architecture Details
- **Network Readiness**: Extensive network validation before any package operations (max 40 attempts, 60s intervals)
- **Outpost Optimization**: Built-in delays and timeouts optimized for AWS Outpost latency  
- **DNF Retries**: Automatic retry logic for package manager operations (3 attempts with 30s delays)
- **SSM Registration**: 180-second wait for SSM agent registration with AWS Systems Manager
- **Component Installation Order**: System updates → SSM agent → Complete Cockpit installation
- **Console Log Monitoring**: Real-time progress monitoring via `aws ec2 get-console-output` (no SSH required)
- **Status Markers**: Creates `/tmp/bootstrap-complete` marker file for external monitoring

### Cockpit Components Installed
- **Core**: cockpit, cockpit-system, cockpit-ws, cockpit-bridge
- **Network & Storage**: cockpit-networkmanager, cockpit-storaged
- **Package Management**: cockpit-packagekit, cockpit-sosreport
- **Virtualization**: cockpit-machines, qemu-kvm, libvirt, virt-install
- **Containers**: cockpit-podman, podman, buildah, skopeo
- **Monitoring**: cockpit-pcp, pcp, pcp-system-tools
- **Third-party Extensions**: cockpit-file-sharing, cockpit-navigator, cockpit-identities, cockpit-sensors (from 45Drives repo)

### Testing and Validation
- **Primary Monitoring**: Console log output parsed for completion markers ("COMPLETE COCKPIT DEPLOYMENT SUCCESS")
- **Error Detection**: Console logs monitored for failure patterns ("Bootstrap.*failed", "ERROR.*failed")
- **Web Interface Test**: Optional curl test to port 9090 (non-blocking)
- **Network Readiness**: Validated against multiple endpoints (Rocky repo, AWS S3)
- **Progress Visibility**: Real-time console output display during bootstrap

### Legacy Migration Notes
- Project migrated from SSM-based modular deployment to self-contained user-data
- All SSM documents removed - functionality consolidated into `user-data-bootstrap.sh`
- Legacy utilities preserved in `legacy/` directory for reference and management operations