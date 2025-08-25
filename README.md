# AWS Outpost Cockpit SSM

Automated deployment of [Cockpit](https://cockpit-project.org/) web console on AWS Outpost instances using a modern **SSM multi-phase architecture**. This project provides idempotent, resumable deployment with excellent error handling and observability.

## 🚀 Quick Start

### Prerequisites
- AWS CLI installed and configured
- AWS Outpost with EC2 instances
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
```bash
# Deploy new instance (recommended)
./launch-cockpit-instance.sh

# Check deployment status
./launch-cockpit-instance.sh --status

# Resume from failure point
./launch-cockpit-instance.sh --resume
```

### 4. Access Cockpit
After deployment completes (~30-45 minutes), access Cockpit at:
- **URL**: `https://YOUR_INSTANCE_IP:9090`
- **Username**: `admin` or `rocky`
- **Password**: `Cockpit123`

## 📋 What Gets Installed

- **Cockpit Web Console**: Complete system management interface
- **Virtualization**: KVM/libvirt with VM management
- **Containers**: Podman with container management interface
- **Storage Management**: Disk and filesystem tools with RAID5 support
- **Enhanced Extensions**: File sharing, navigation, identity management (45Drives)

## 📂 Basic Commands

```bash
# Check deployment status
./launch-cockpit-instance.sh --status

# List available phases
./launch-cockpit-instance.sh --list-phases

# Run specific phase
./launch-cockpit-instance.sh --phase cockpit-core

# Instance management
./legacy/manage-instances.sh status
./legacy/manage-instances.sh ssh
./legacy/manage-instances.sh terminate
```

## 📁 Project Structure

```
.
├── launch-cockpit-instance.sh       # Main deployment script
├── user-data-minimal.sh             # Minimal bootstrap (network + SSM agent)
├── ssm-documents/                   # SSM deployment phases
├── legacy/manage-instances.sh       # Instance operations utility
├── .env.example                     # Environment template
└── ${KEY_NAME}.pem                 # SSH private key (user-provided)
```

## 📚 Documentation

- **[USAGE.md](USAGE.md)** - Detailed commands, troubleshooting, and operations guide
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Technical deep-dive into SSM deployment architecture
- **[legacy/README.md](legacy/README.md)** - Legacy architecture documentation

## ⭐ Key Features

- 🔄 **Idempotent Deployment** - Safe to re-run, automatic resume from failures
- 📊 **Real-time Monitoring** - AWS console integration with phase-specific logs  
- 🎯 **Phase-Specific Control** - Individual phase execution and retry
- 🚀 **One-Command Deploy** - Simple setup with comprehensive functionality
- 🛡️ **Resilient Error Handling** - Individual phase failures don't stop deployment

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes with `./launch-cockpit-instance.sh --status`
4. Update documentation if needed
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Ready to deploy?** Run `./launch-cockpit-instance.sh` and watch the magic happen! ✨

**Need help?** Check [USAGE.md](USAGE.md) for detailed operations guide.