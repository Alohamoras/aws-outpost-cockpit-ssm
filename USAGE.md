# Usage Guide

Comprehensive guide for managing and operating AWS Outpost Cockpit deployments.

## 📊 Deployment Status & Monitoring

### Beautiful Status Display
```bash
# Check current deployment state
./launch-cockpit-instance.sh --status
```

Example output:
```
╭─────────────────────────────────────────────╮
│          DEPLOYMENT STATUS                  │
╰─────────────────────────────────────────────╯
Instance ID: i-01234567890abcdef
Public IP:   3.82.8.10

Phase Status:
┌────────────────────────────────────┬──────────────┐
│ Phase                              │ Status       │
├────────────────────────────────────┼──────────────┤
│ Minimal Bootstrap                  │ ✅ Complete  │
│ System Updates                     │ ✅ Complete  │
│ Storage Configuration              │ ✅ Complete  │
│ Core Cockpit Installation          │ ✅ Complete  │
│ Cockpit Extensions                 │ ⏸️  Pending   │
│ Third-party Extensions             │ ⏸️  Pending   │
│ Final Configuration                │ ⏸️  Pending   │
└────────────────────────────────────┴──────────────┘

Next phase to run: cockpit-extensions
    Resume with: ./launch-cockpit-instance.sh --resume
    Run phase:   ./launch-cockpit-instance.sh --phase cockpit-extensions
```

### Real-time Monitoring
```bash
# Monitor via AWS Console
# Systems Manager > Command History > Filter by Instance ID

# Monitor via CLI
aws ssm list-commands --region $REGION --instance-id $INSTANCE_ID

# Check specific phase status
aws ssm get-command-invocation --region $REGION --command-id $COMMAND_ID --instance-id $INSTANCE_ID
```

### Phase-Specific Logs
Each phase creates its own log file on the instance:
```bash
/var/log/user-data-bootstrap.log      # Phase 1 (minimal bootstrap)
/var/log/ssm-system-updates.log       # Phase 2 (system updates)
/var/log/ssm-cockpit-core.log         # Phase 3 (core cockpit)
/var/log/ssm-cockpit-extensions.log   # Phase 4 (extensions)
/var/log/ssm-cockpit-thirdparty.log   # Phase 5 (third-party)
/var/log/ssm-cockpit-config.log       # Phase 6 (final config)
```

## 🛠️ Management Commands

### Primary Deployment Operations
```bash
# List available phases
./launch-cockpit-instance.sh --list-phases

# Run specific phase
./launch-cockpit-instance.sh --phase system-updates
./launch-cockpit-instance.sh --phase cockpit-core

# Force new deployment (terminates existing)
./launch-cockpit-instance.sh --force-new

# Show help with all options
./launch-cockpit-instance.sh --help
```

### Instance Operations
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

### Direct SSM Operations
```bash
# Re-execute a specific phase via SSM
aws ssm send-command \
  --region $REGION \
  --document-name "outpost-cockpit-core" \
  --instance-ids $INSTANCE_ID
```

## 🔧 Troubleshooting

### Common Issues

#### Deployment Stuck/Failed
```bash
# Check current status with detailed phase information
./launch-cockpit-instance.sh --status

# Resume from failure point
./launch-cockpit-instance.sh --resume

# Monitor AWS SSM console for detailed execution logs
# Systems Manager > Command History > [Command ID] > Output
```

#### Phase-Specific Failures
```bash
# Re-run failed phase
./launch-cockpit-instance.sh --phase <phase-name>

# Check phase logs on instance
ssh -i ${KEY_NAME}.pem rocky@$PUBLIC_IP 'sudo tail -f /var/log/ssm-<phase>.log'

# Check AWS SSM command output
aws ssm get-command-invocation \
  --region $REGION \
  --command-id $COMMAND_ID \
  --instance-id $INSTANCE_ID \
  --query 'StandardErrorContent' \
  --output text
```

#### Instance Not Accessible
- Verify security group allows port 9090 (HTTPS) and 22 (SSH)
- Check if public IP was assigned correctly
- Confirm instance is in 'running' state

#### SSM Agent Issues
```bash
# Check SSM agent status
aws ssm describe-instance-information \
  --region $REGION \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID"

# Verify IAM permissions for SSM
aws iam list-attached-role-policies \
  --role-name AmazonSSMManagedInstanceCore
```

### Advanced Troubleshooting

#### Network Connectivity Issues
The minimal bootstrap includes extensive network validation:
- Tests multiple endpoints (Rocky repo, AWS S3)
- Up to 40 attempts with 60-second intervals
- Optimized for AWS Outpost latency patterns

#### Package Installation Failures
Each SSM phase includes retry logic:
- 3 attempts per DNF operation
- 30-second delays between attempts
- Graceful handling of unavailable packages

#### Service Startup Issues
```bash
# Check critical services on instance
ssh -i ${KEY_NAME}.pem rocky@$PUBLIC_IP 'systemctl status cockpit.socket libvirtd podman.socket'

# Restart services if needed
ssh -i ${KEY_NAME}.pem rocky@$PUBLIC_IP 'sudo systemctl restart cockpit.socket'
```

## 🔐 Security Considerations

### User Accounts
- Default users: `admin` and `rocky` (both with password: `Cockpit123`)
- Both users have sudo access via wheel group membership
- Users configured for Cockpit access with virtualization and container permissions

### Network Security
- Cockpit accessible on port 9090 (HTTPS)
- SSH access on port 22 for management
- Security groups must allow these ports from appropriate IP ranges

### SSH Keys
- SSH private keys are gitignored and never committed
- Key permissions automatically set to 400 during execution
- Users must provide their own SSH private key

### AWS IAM Requirements
The deployment requires these IAM permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:CreateDocument",
                "ssm:UpdateDocument", 
                "ssm:SendCommand",
                "ssm:GetCommandInvocation",
                "ssm:DescribeInstanceInformation"
            ],
            "Resource": "*"
        }
    ]
}
```

## 🚀 Performance & Timing

### Deployment Timeline
- **Phase 1**: Network + SSM setup (5-10 minutes)
- **Phase 2**: System updates (10-15 minutes) 
- **Phase 3**: Core Cockpit (5-10 minutes)
- **Phase 4**: Extensions (15-20 minutes)
- **Phase 5**: Third-party (5-10 minutes) - *Optional*
- **Phase 6**: Final config (2-5 minutes)

**Total Time**: ~30-45 minutes (vs 45-60 minutes for legacy)

### Architecture Comparison

| Aspect | Legacy Architecture | SSM Architecture |
|--------|-------------------|------------------|
| **Total Time** | 45-60 minutes | 30-45 minutes |
| **Error Recovery** | All-or-nothing restart | Selective phase retry |
| **Observability** | Single log file | Phase-specific logs + AWS console |
| **Maintainability** | 378-line monolith | 5 focused documents |
| **Testing** | Full deployment required | Individual phase testing |
| **Debugging** | SSH required for logs | AWS console logs |
| **Idempotency** | None | Full resume capability |

## 💾 Storage Configuration

The storage configuration phase automatically optimizes storage for Cockpit workloads:

### Boot Drive Extension
- **Smart Detection**: Automatically detects boot drive (supports NVMe and SATA)
- **LVM Extension**: Extends existing Rocky Linux volume group with available space
- **Non-disruptive**: Extends root filesystem without interrupting operations
- **Minimum Threshold**: Only extends if >10GB free space available

### RAID5 Data Array (3+ drives)
- **Automatic Detection**: Identifies unused data drives (excludes boot drive)
- **RAID5 Creation**: Creates fault-tolerant array for enterprise storage
- **LVM Integration**: Sets up LVM volume group "data" on RAID array
- **Safety Checks**: Prevents data loss by excluding drives with existing data

### Workload-Optimized Volumes
When RAID5 array is available, creates optimized logical volumes:
- **VM Storage** (`/var/lib/libvirt`): 40% of available space for virtual machines
- **Container Storage** (`/var/lib/containers`): 30% of available space for Podman containers  
- **General Storage** (`/storage`): 25% of available space for file sharing and data
- **XFS Filesystems**: High-performance filesystems optimized for large files
- **Automatic Mounting**: Configured in `/etc/fstab` for persistent mounts

### Smart Behavior
- **Graceful Fallback**: If <3 drives available, only extends boot drive
- **Non-Critical**: Storage configuration failure doesn't stop Cockpit deployment
- **Idempotent**: Safe to re-run, detects existing configuration

## 📋 Command Reference

### All Available Phases
1. **bootstrap** - Network readiness and SSM agent setup
2. **system-updates** - System package updates and AWS CLI
3. **storage-config** - RAID5 setup and storage optimization
4. **cockpit-core** - Core Cockpit packages and configuration
5. **cockpit-extensions** - Virtualization, containers, and monitoring
6. **cockpit-thirdparty** - 45Drives extensions (optional)
7. **cockpit-config** - Final configuration and user setup

### Launcher Options
```bash
./launch-cockpit-instance.sh [OPTIONS]

Options:
  --status         Show current deployment status
  --resume         Resume deployment from failure point
  --phase <name>   Run specific deployment phase
  --list-phases    List all available phases
  --force-new      Terminate existing and start new deployment
  --help           Show this help message
```