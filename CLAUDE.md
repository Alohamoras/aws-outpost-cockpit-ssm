# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project automates the deployment of Cockpit web console on AWS Outpost instances using AWS SSM (Systems Manager) automation. It provides infrastructure-as-code for launching EC2 instances and configuring them with Cockpit for server management.

## Architecture

The system uses a modern SSM-based architecture that replaced the original monolithic user-data scripts:

### Current SSM Architecture
- **Main launcher**: `launch-cockpit-instance.sh` - Orchestrates the entire deployment
- **SSM automation**: Uses AWS SSM documents for reliable, monitored installation
- **Bootstrap script**: `user-data-bootstrap.sh` - Minimal instance initialization
- **Instance management**: `legacy/manage-instances.sh` - Operations utilities

### Key Components
- EC2 instance launch with Rocky Linux 9
- IAM role and instance profile management for SSM
- SNS notifications for installation progress
- Elastic IP assignment and network configuration
- Cockpit installation via SSM automation documents

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
   - `SSM_MAIN_DOCUMENT` - Main orchestration document (default: cockpit-deploy-automation)
   - `CONTINUE_ON_ERROR` - Continue deployment if non-critical components fail (default: true)
   - `AUTOMATION_ASSUME_ROLE` - IAM role for automation execution (optional)

### SSH Key
- The project expects `ryanfill.pem` SSH private key in the root directory
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
- Launch instance with minimal bootstrap
- Execute SSM automation for Cockpit installation
- Provide monitoring options and final URLs

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

### Component Retry
If SSM automation fails, retry specific components individually:
```bash
# Individual component retry
aws ssm send-command --document-name cockpit-system-prep --instance-ids $INSTANCE_ID
aws ssm send-command --document-name cockpit-core-install --instance-ids $INSTANCE_ID
aws ssm send-command --document-name cockpit-services-setup --instance-ids $INSTANCE_ID
aws ssm send-command --document-name cockpit-extensions --instance-ids $INSTANCE_ID
aws ssm send-command --document-name cockpit-user-config --instance-ids $INSTANCE_ID
aws ssm send-command --document-name cockpit-finalize --instance-ids $INSTANCE_ID

# Or restart full automation
aws ssm start-automation-execution --document-name cockpit-deploy-automation \
  --parameters "InstanceId=$INSTANCE_ID,NotificationTopic=$SNS_TOPIC_ARN"
```

## SSM Documents

The system depends on these SSM automation documents (must be deployed separately):
- `cockpit-base-install` - Main installation automation
- `cockpit-deploy-automation` - Alternative deployment document
- `cockpit-finalize` - Final configuration steps

## File Structure

```
.
├── launch-cockpit-instance.sh    # Main launcher (SSM architecture)
├── user-data-bootstrap.sh        # Minimal instance bootstrap
├── .env.example                  # Environment template
├── .env                         # Local configuration (gitignored)
├── ryanfill.pem                 # SSH private key
├── .last-instance-id            # Tracks most recent instance
└── legacy/                      # Legacy scripts directory
    ├── README.md                # Legacy documentation
    └── manage-instances.sh      # Instance operations utility (still used)
```

## Development Notes

### Instance State Tracking
- Instance details are stored in `.last-instance-id` after launch
- Contains instance ID, public IP, and execution ID for management operations

### Networking
- Instances require public IP access for Cockpit web interface
- Script automatically assigns available Elastic IP if needed
- Cockpit accessible on port 9090 (HTTPS)

### Error Handling
- All scripts use `set -e` for fail-fast behavior
- Comprehensive logging with color-coded output
- SNS notifications for installation progress and failures
- Retry mechanisms for failed automation components