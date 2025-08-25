# AWS Outpost Cockpit SSM

Automated deployment of [Cockpit](https://cockpit-project.org/) web console on AWS Outpost instances using a modern **SSM multi-phase architecture**. This project provides idempotent, resumable deployment with excellent error handling and observability.

## 🚀 Quick Start

### Prerequisites
- AWS CLI installed and configured
- AWS Outpost with EC2 instances
- SNS topic for notifications (required for progress updates)
- SSH key pair for instance access

### 1. Setup Configuration
```bash
# Clone the repository
git clone https://github.com/Alohamoras/aws-outpost-cockpit-ssm.git
cd aws-outpost-cockpit-ssm

# Copy and configure environment
cp .env.example .env
# Edit .env with your AWS configuration
```

Required `.env` configuration:
```bash
OUTPOST_ID=your-outpost-id
SUBNET_ID=your-subnet-id
SECURITY_GROUP_ID=your-security-group-id
KEY_NAME=your-key-name
SNS_TOPIC_ARN=your-sns-topic-arn
REGION=us-east-1
```

### 2. Add SSH Key
```bash
# Copy your SSH private key to the project directory
# Name it based on your KEY_NAME in .env (e.g., if KEY_NAME=mykey, copy as mykey.pem)
cp /path/to/your-private-key.pem ${KEY_NAME}.pem
chmod 400 ${KEY_NAME}.pem
```

### 3. Deploy Cockpit

#### Smart Idempotent Deployment (Recommended)
```bash
# Launches new instance or resumes existing deployment
./launch-cockpit-instance.sh

# Check current deployment status
./launch-cockpit-instance.sh --status

# Resume from failure point
./launch-cockpit-instance.sh --resume

# Run specific phase only
./launch-cockpit-instance.sh --phase cockpit-core
```

#### Alternative Command Line Options
```bash
# Force new deployment (terminates existing)
./launch-cockpit-instance.sh --force-new

# List all available phases
./launch-cockpit-instance.sh --list-phases

# Show help with all options
./launch-cockpit-instance.sh --help
```

### 4. Access Cockpit
After deployment completes (~30-45 minutes), access Cockpit at:
- **URL**: `https://YOUR_INSTANCE_IP:9090`
- **Username**: `admin` or `rocky`
- **Password**: `Cockpit123`

## 🏗️ Architecture

### SSM Multi-Phase Deployment
The deployment uses AWS Systems Manager for reliable, observable deployment across 7 phases:

#### Phase 1: Minimal User-Data Bootstrap
- **File**: `user-data-minimal.sh` (~40 lines vs 378 in legacy)
- **Purpose**: Network readiness validation and SSM agent setup
- **Duration**: ~5-10 minutes
- **Critical**: Must complete successfully for SSM phases to work

#### Phase 2-7: SSM Document Execution
Executed sequentially by the launcher via AWS Systems Manager:

1. **System Updates** (`outpost-system-updates.json`)
   - System package updates and AWS CLI verification
   - Duration: ~10-15 minutes

2. **Storage Configuration** (`outpost-storage-config.json`)
   - RAID5 setup for data drives (3+ drives required)
   - Root OS volume extension using available space
   - LVM volume creation for VMs, containers, and storage
   - Duration: ~5-15 minutes
   - Non-critical: Deployment continues if this fails

3. **Core Cockpit** (`outpost-cockpit-core.json`)
   - Core Cockpit packages and basic configuration
   - Duration: ~5-10 minutes

4. **Cockpit Extensions** (`outpost-cockpit-extensions.json`)
   - Virtualization, containers, and monitoring packages
   - Duration: ~15-20 minutes
   - Non-critical: Deployment continues if this fails

5. **Third-party Extensions** (`outpost-cockpit-thirdparty.json`)
   - 45Drives extensions for enhanced functionality
   - Duration: ~5-10 minutes
   - Non-critical: Deployment continues if this fails

6. **Final Configuration** (`outpost-cockpit-config.json`)
   - User accounts, final settings, and verification
   - Duration: ~2-5 minutes

### Key Architecture Benefits

#### ✅ **Idempotent Operations**
- Safe to re-run, resumes from failure points
- Smart state detection prevents duplicate work
- Individual phase retry without full restart

#### ✅ **Enhanced Observability** 
- Real-time progress via AWS console and SNS
- Phase-specific logs for targeted troubleshooting
- Built-in progress tracking and status reporting

#### ✅ **Resilient Error Handling**
- Individual phase failure doesn't stop everything
- Non-critical phases can fail gracefully
- Built-in retry mechanisms and timeout handling

#### ✅ **Maintainable Design**
- Separate, focused deployment phases (5 SSM documents)
- Clear separation of concerns
- Version-controlled deployment artifacts

#### ✅ **AWS-Native Integration**
- Leverages SSM for enterprise-grade deployment
- Better integration with AWS monitoring and alerting
- No SSH dependencies for remote execution

## 📋 What Gets Installed

### Core Components
- **Cockpit Web Console**: Complete system management interface
- **Virtualization**: KVM/libvirt with VM management (cockpit-machines)
- **Containers**: Podman with container management interface
- **Storage Management**: Disk and filesystem tools
- **Package Management**: Software installation interface
- **Network Management**: Network configuration tools

### Enhanced Extensions (45Drives)
- **File Sharing**: SMB/CIFS sharing interface
- **Navigator**: Enhanced file browser
- **Identity Management**: User and group management
- **System Reports**: Comprehensive system reporting

### 💾 Storage Configuration

The storage configuration phase automatically optimizes storage for Cockpit workloads:

#### Boot Drive Extension
- **Smart Detection**: Automatically detects boot drive (supports NVMe and SATA)
- **LVM Extension**: Extends existing Rocky Linux volume group with available space
- **Non-disruptive**: Extends root filesystem without interrupting operations
- **Minimum Threshold**: Only extends if >10GB free space available

#### RAID5 Data Array (3+ drives)
- **Automatic Detection**: Identifies unused data drives (excludes boot drive)
- **RAID5 Creation**: Creates fault-tolerant array for enterprise storage
- **LVM Integration**: Sets up LVM volume group "data" on RAID array
- **Safety Checks**: Prevents data loss by excluding drives with existing data

#### Workload-Optimized Volumes
When RAID5 array is available, creates optimized logical volumes:
- **VM Storage** (`/var/lib/libvirt`): 40% of available space for virtual machines
- **Container Storage** (`/var/lib/containers`): 30% of available space for Podman containers  
- **General Storage** (`/storage`): 25% of available space for file sharing and data
- **XFS Filesystems**: High-performance filesystems optimized for large files
- **Automatic Mounting**: Configured in `/etc/fstab` for persistent mounts

#### Smart Behavior
- **Graceful Fallback**: If <3 drives available, only extends boot drive
- **Non-Critical**: Storage configuration failure doesn't stop Cockpit deployment
- **Idempotent**: Safe to re-run, detects existing configuration
- **Progress Notifications**: SNS updates for storage configuration progress

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
  --instance-ids $INSTANCE_ID \
  --parameters "snsTopicArn=$SNS_TOPIC_ARN,instanceId=$INSTANCE_ID"
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
- Ensure SNS topic ARN is valid for notifications
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

## 📁 Project Structure

```
.
├── launch-cockpit-instance.sh       # Complete SSM multi-phase launcher
├── user-data-minimal.sh             # Minimal bootstrap (network + SSM agent)
├── ssm-documents/                   # SSM deployment phases
│   ├── outpost-system-updates.json
│   ├── outpost-cockpit-core.json
│   ├── outpost-cockpit-extensions.json
│   ├── outpost-cockpit-thirdparty.json
│   └── outpost-cockpit-config.json
├── .env.example                     # Environment template
├── .env                            # Local configuration (gitignored)
├── ${KEY_NAME}.pem                 # SSH private key (user-provided, gitignored)
├── .last-instance-id               # Tracks most recent instance state
└── legacy/                         # Legacy scripts and utilities
    ├── launch-cockpit-instance-legacy.sh   # Original monolithic launcher
    ├── user-data-bootstrap-legacy.sh       # Original bootstrap (preserved)
    ├── manage-instances.sh                  # Instance operations utility
    └── README.md                            # Legacy documentation
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
| **Debugging** | SSH required for logs | AWS console + SNS notifications |
| **Idempotency** | None | Full resume capability |

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
                "ssm:DescribeInstanceInformation",
                "sns:Publish"
            ],
            "Resource": "*"
        }
    ]
}
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes thoroughly with the idempotent launcher
4. Update documentation if needed
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Guidelines
- Test with `./launch-cockpit-instance.sh --status` for state validation
- Use `./launch-cockpit-instance.sh --phase <phase>` for targeted testing
- Verify idempotency with multiple runs
- Check AWS console for SSM execution logs

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⭐ Features

- 🔄 **Idempotent Deployment**: Safe to re-run, automatic resume from failures
- 📊 **Real-time Monitoring**: AWS console integration + SNS notifications  
- 🎯 **Phase-Specific Control**: Individual phase execution and retry
- 🏗️ **Enterprise Architecture**: AWS SSM-based deployment pipeline
- 📱 **Complete Web Management**: Full-featured Cockpit installation
- 🚀 **One-Command Deploy**: Simple setup with comprehensive functionality
- 🛡️ **Resilient Error Handling**: Individual phase failures don't stop deployment
- 📈 **Beautiful Status Display**: Clear progress tracking with next steps
- 🔧 **Granular Control**: Run, retry, or skip individual deployment phases
- ☁️ **AWS-Native**: Leverages SSM, SNS, and EC2 for enterprise-grade deployment

---

**Ready to deploy?** Run `./launch-cockpit-instance.sh` and watch the magic happen! ✨

**Need help?** Use `./launch-cockpit-instance.sh --help` for all available options.