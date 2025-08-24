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

#### Full SSM Multi-Phase Deployment
```bash
# Complete deployment with AWS SSM orchestration
./launch-cockpit-instance-ssm.sh
```

### 4. Access Cockpit
After deployment completes (~30-45 minutes), access Cockpit at:
- **URL**: `https://YOUR_INSTANCE_IP:9090`
- **Username**: `admin` or `rocky`
- **Password**: `Cockpit123`

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

## 🏗️ Architecture

### SSM Multi-Phase Deployment
The deployment uses AWS Systems Manager for reliable, observable deployment:

1. **Phase 1**: Network readiness and SSM agent setup (minimal user-data)
2. **Phase 2**: System updates and AWS CLI installation
3. **Phase 3**: Core Cockpit installation and configuration
4. **Phase 4**: Extensions (virtualization, containers, monitoring)
5. **Phase 5**: Third-party enhancements (45Drives extensions)
6. **Phase 6**: Final configuration and user setup

### Key Benefits
- ✅ **Idempotent**: Safe to re-run, resumes from failure points
- ✅ **Observable**: Real-time progress via AWS console and SNS
- ✅ **Resilient**: Individual phase retry without full restart  
- ✅ **Maintainable**: Separate, focused deployment phases
- ✅ **AWS-Native**: Leverages SSM for enterprise-grade deployment

## 📊 Deployment Status

### Monitor Progress
```bash
# Beautiful status display
./launch-cockpit-instance.sh --status

# Monitor via AWS Console
# Systems Manager > Command History > Filter by Instance ID
```

### Phase Status Example
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
│ Core Cockpit Installation          │ ✅ Complete  │
│ Cockpit Extensions                 │ ⏸️  Pending   │
│ Third-party Extensions             │ ⏸️  Pending   │
│ Final Configuration                │ ⏸️  Pending   │
└────────────────────────────────────┴──────────────┘
```

## 🛠️ Management Commands

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

### Phase-Specific Operations
```bash
# List available phases
./launch-cockpit-instance.sh --list-phases

# Run specific phase
./launch-cockpit-instance.sh --phase system-updates
./launch-cockpit-instance.sh --phase cockpit-core

# Force new deployment (terminates existing)
./launch-cockpit-instance.sh --force-new
```

## 🔧 Troubleshooting

### Common Issues

#### Deployment Stuck/Failed
```bash
# Check current status
./launch-cockpit-instance.sh --status

# Resume from failure
./launch-cockpit-instance.sh --resume

# Monitor AWS SSM console for detailed logs
```

#### Phase-Specific Failures
```bash
# Re-run failed phase
./launch-cockpit-instance.sh --phase <phase-name>

# Check phase logs on instance
ssh -i ${KEY_NAME}.pem rocky@$PUBLIC_IP 'sudo tail -f /var/log/ssm-<phase>.log'
```

#### Instance Not Accessible
- Verify security group allows port 9090 (HTTPS) and 22 (SSH)
- Check if public IP was assigned correctly
- Ensure SNS topic ARN is valid for notifications

### Log Locations
Phase-specific logs on the instance:
```
/var/log/user-data-bootstrap.log      # Phase 1 (minimal bootstrap)
/var/log/ssm-system-updates.log       # Phase 2 (system updates)
/var/log/ssm-cockpit-core.log         # Phase 3 (core cockpit)
/var/log/ssm-cockpit-extensions.log   # Phase 4 (extensions)
/var/log/ssm-cockpit-thirdparty.log   # Phase 5 (third-party)
/var/log/ssm-cockpit-config.log       # Phase 6 (final config)
```

## 📚 Documentation

- **README-SSM-Architecture.md**: Comprehensive architecture documentation
- **CLAUDE.md**: Development and project guidance
- **.env.example**: Environment configuration template

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ⭐ Features

- 🔄 **Idempotent Deployment**: Safe to re-run, automatic resume
- 📊 **Real-time Monitoring**: AWS console integration + SNS notifications  
- 🎯 **Phase-Specific Control**: Individual phase execution and retry
- 🏗️ **Enterprise Architecture**: AWS SSM-based deployment pipeline
- 📱 **Complete Web Management**: Full-featured Cockpit installation
- 🚀 **One-Command Deploy**: Simple setup with comprehensive functionality

---

**Ready to deploy?** Run `./launch-cockpit-instance.sh` and watch the magic happen! ✨