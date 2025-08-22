# AWS Systems Manager Documents for Cockpit Deployment

This directory contains AWS SSM documents for installing and configuring Cockpit on AWS Outpost instances.

## Current Architecture - Simplified Single Document

### 🎯 **Main Installation Document**
- `cockpit-complete-install.yaml` - Complete Cockpit installation in a single document

## Benefits of Simplified Architecture

### ✅ **Simplicity**
- Single document with all components in logical sections
- Direct parameter substitution (no complex orchestration)
- Simple `aws ssm send-command` execution
- Single log file for easy debugging

### ✅ **Reliability**
- No complex automation orchestration points of failure
- Direct SNS notifications work reliably
- Faster execution (no automation overhead)
- Clear component progress tracking

### ✅ **Maintainability**
- 90% less complexity than previous modular approach
- Easy to understand complete workflow in one file
- Simple to modify and test changes
- No JSON/YAML format conversion issues

## Usage

### Quick Deployment
```bash
# Deploy the SSM document
aws ssm create-document --name "cockpit-complete-install" --content file://ssm-documents/cockpit-complete-install.yaml --document-type "Command"

# Launch instance with automated Cockpit installation
./launch-cockpit-instance.sh
```

### Manual Execution
```bash
# Execute complete installation
aws ssm send-command \
  --document-name "cockpit-complete-install" \
  --instance-ids $INSTANCE_ID \
  --parameters "InstanceId=$INSTANCE_ID,NotificationTopic=$SNS_TOPIC_ARN"
```

### Monitor Progress
```bash
# Use simplified monitoring script
./scripts/monitor-command.sh $COMMAND_ID $INSTANCE_ID
```

## Installation Components

The single document includes these logical sections:

1. **System Preparation** - System updates, AWS CLI, SSM agent, network readiness
2. **Core Cockpit Installation** - Core Cockpit packages and services
3. **Extended Services Setup** - Virtualization, containers, monitoring
4. **Third-party Extensions** - 45Drives modules, file sharing
5. **User Configuration** - User accounts, sudo access
6. **Final Configuration** - Verification and completion

## Parameters

- `InstanceId` - Target EC2 instance ID  
- `NotificationTopic` - SNS topic ARN for progress notifications

## Monitoring & Notifications

- **Real-time progress**: SNS emails sent at each major component completion
- **Component tracking**: Monitor script shows progress through each installation phase
- **Single log file**: `/var/log/cockpit-complete-install.log` contains complete installation log

## Troubleshooting

### Check Command Status
```bash
aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $INSTANCE_ID
```

### View Installation Logs
```bash
ssh -i key.pem rocky@$IP sudo tail -f /var/log/cockpit-complete-install.log
```

### Retry Installation
```bash
aws ssm send-command --document-name "cockpit-complete-install" --instance-ids $INSTANCE_ID
```

## Legacy Architecture

The previous complex modular architecture (7 separate documents with automation orchestration) has been moved to `legacy/` directory. The simplified approach provides the same functionality with dramatically reduced complexity.