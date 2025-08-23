# AWS Outpost Cockpit SSM

Automated deployment of [Cockpit](https://cockpit-project.org/) web console on AWS Outpost instances using a self-contained user-data bootstrap approach. This project provides a streamlined, single-script deployment with complete Cockpit installation during instance launch.

## 🚀 Quick Start

### Prerequisites
- AWS CLI installed and configured
- AWS Outpost with EC2 instances
- SNS topic for notifications (recommended)
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

### 2. Launch Cockpit Instance
```bash
# Add your SSH key to the directory
cp /path/to/your-key.pem ryanfill.pem

# Launch instance with complete self-contained Cockpit installation
./launch-cockpit-instance.sh
```

### 3. Access Cockpit
After deployment completes (20-45 minutes), access Cockpit at:
- **URL**: `https://YOUR_INSTANCE_IP:9090`
- **Username**: `admin` or `rocky`
- **Password**: `Cockpit123`

## 📋 What Gets Installed

- **Core Cockpit**: Web console with system management
- **Virtualization**: KVM/libvirt support with VM management
- **Containers**: Podman with container management interface
- **Performance Monitoring**: PCP integration for metrics
- **Storage Management**: Disk and filesystem tools
- **Network Configuration**: NetworkManager integration
- **Third-party Extensions**: File manager, hardware sensors (bare metal)

## 🏗️ Architecture

### Modular SSM Documents
The installation is broken into manageable, reusable components:

```
cockpit-deploy-automation (Main Orchestrator)
├── cockpit-system-prep      → System preparation & dependencies
├── cockpit-core-install     → Core Cockpit installation
├── cockpit-services-setup   → Virtualization, containers, monitoring
├── cockpit-extensions       → Third-party modules & hardware config
├── cockpit-user-config      → User accounts & security
└── cockpit-finalize         → Final configuration & notifications
```

### Key Benefits
- **Reliability**: Component-level error handling and retry capabilities
- **Visibility**: SNS notifications for each deployment phase
- **Modularity**: Individual components can be run independently
- **Maintainability**: Smaller, focused documents are easier to modify
- **Outpost Optimization**: Network delays and hardware detection built-in

## 🛠️ Management Operations

### Instance Management
```bash
# Check instance status
./legacy/manage-instances.sh status

# SSH into instance
./legacy/manage-instances.sh ssh

# Monitor installation logs
./legacy/manage-instances.sh logs

# Open Cockpit in browser
./legacy/manage-instances.sh cockpit

# Check service health
./legacy/manage-instances.sh services

# Terminate instance
./legacy/manage-instances.sh terminate
```

### Component Retry
If a component fails, retry individually:
```bash
# Retry specific components
aws ssm send-command --document-name cockpit-core-install --instance-ids $INSTANCE_ID
aws ssm send-command --document-name cockpit-services-setup --instance-ids $INSTANCE_ID

# Or restart full automation
aws ssm start-automation-execution --document-name cockpit-deploy-automation \
  --parameters "InstanceId=$INSTANCE_ID,NotificationTopic=$SNS_TOPIC_ARN"
```

## ⚙️ Configuration

### Environment Variables (.env)
```bash
# AWS Infrastructure
OUTPOST_ID=op-0123456789abcdef0
SUBNET_ID=subnet-0123456789abcdef0  
SECURITY_GROUP_ID=sg-0123456789abcdef0
KEY_NAME=your-key-pair-name
INSTANCE_TYPE=c6id.metal
REGION=us-east-1

# Notifications (required)
SNS_TOPIC_ARN=arn:aws:sns:us-east-1:123456789012:topic-name

# Deployment Options
SSM_MAIN_DOCUMENT=cockpit-deploy-automation
CONTINUE_ON_ERROR=true
AUTOMATION_ASSUME_ROLE=
```

### Security Group Requirements
Ensure your security group allows:
- **Inbound TCP 9090** - Cockpit web interface
- **Inbound TCP 22** - SSH access
- **Outbound HTTPS** - Package downloads and SSM communication

## 📊 Monitoring & Troubleshooting

### Deployment Monitoring
- **SNS Notifications**: Real-time progress updates via email/SMS
- **AWS Console**: SSM automation execution in AWS Systems Manager
- **Instance Logs**: Component-specific logs in `/var/log/cockpit-*.log`

### Common Issues
- **Network Timeouts**: Outpost instances have built-in delays for network stabilization
- **Package Failures**: Retry logic handles temporary repository issues
- **Service Startup**: Non-critical services can be skipped with `CONTINUE_ON_ERROR=true`

### Log Files
```bash
/var/log/user-data-bootstrap.log    # Initial instance preparation
/var/log/cockpit-system-prep.log    # System preparation component
/var/log/cockpit-core-install.log   # Core installation component
/var/log/cockpit-services-setup.log # Services setup component
/var/log/cockpit-extensions.log     # Extensions component
/var/log/cockpit-user-config.log    # User configuration component
/var/log/cockpit-finalize.log       # Final configuration component
```

## 📚 Documentation

- **[CLAUDE.md](CLAUDE.md)** - Comprehensive development guide
- **[legacy/README.md](legacy/README.md)** - Migration information

## 🧪 Testing

### Instance Testing
```bash
# Launch instance with complete installation
./launch-cockpit-instance.sh

# Monitor bootstrap progress (SSH into instance)
ssh -i ryanfill.pem rocky@<instance-ip> 'sudo tail -f /var/log/user-data-bootstrap.log'

# Verify services after completion
./legacy/manage-instances.sh services
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes on an AWS Outpost instance
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## 📝 License

This project is released into the public domain under The Unlicense - see the [LICENSE](LICENSE) file for details. You can do whatever you want with this code!

## 🙏 Acknowledgments

- [Cockpit Project](https://cockpit-project.org/) - Web-based server management interface
- [45Drives](https://github.com/45Drives) - Third-party Cockpit modules
- [AWS Systems Manager](https://aws.amazon.com/systems-manager/) - Automation platform

## 🔧 Architecture Evolution

This project has evolved from SSM-based modular deployment to a streamlined self-contained user-data approach. The current implementation provides complete Cockpit installation during instance bootstrap with no external dependencies. Legacy SSM components and utilities have been preserved in the `legacy/` directory for reference.

---

**Need Help?** Check the [CLAUDE.md documentation](CLAUDE.md) or open an issue.