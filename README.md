# AWS Outpost Cockpit SSM

Automated deployment of [Cockpit](https://cockpit-project.org/) web console on AWS Outpost instances using a modern **SSM multi-phase architecture**. This project provides idempotent, resumable deployment with excellent error handling and observability.

## 💡 Why This Project Exists

This project demonstrates the art of the possible with AWS Outpost servers. Why put a hypervisor on top of EC2 on an Outpost? **Disconnected operations flexibility.** 

When you run virtualization directly on Outpost instances, you can manage your entire infrastructure while disconnected from the AWS region. This gives you the flexibility to build the cloud integrations that make sense for your workload while restricting dependencies as required for your specific use case.

We chose Cockpit because it's built on a rock-solid OS foundation with a growing community and excellent web-based management interface. It provides enterprise-grade virtualization capabilities without the complexity and licensing costs of traditional hypervisor solutions.

This approach is particularly valuable for:
- **Edge locations** with intermittent connectivity
- **Regulated environments** requiring air-gapped operations  
- **Hybrid workloads** needing both cloud integration and local autonomy
- **Development environments** where you need more control over the virtualization stack

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

# Optional LNI Configuration
ENABLE_LNI=false                    # Enable Local Network Interface creation
LNI_COUNT=1                         # Number of LNIs to create (1-15)
LNI_DHCP_ENABLED=true              # Use DHCP for IP assignment
LNI_STATIC_IPS=""                  # Comma-separated static IPs (optional)
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
- **Virtualization**: KVM/libvirt with VM management via dedicated LNI networking
- **Containers**: Podman with container management interface
- **Storage Management**: Disk and filesystem tools with RAID5 support
- **Enhanced Extensions**: File sharing, navigation, identity management (45Drives)
- **Local Network Interfaces (Optional)**: Direct on-premises network access for VMs/containers

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

## 🌐 Local Network Interface (LNI) Support

Configure optional Local Network Interfaces for direct on-premises VM/container networking:

### LNI Configuration
```bash
# In your .env file
ENABLE_LNI=true                     # Enable LNI creation during deployment
LNI_COUNT=2                         # Create 2 LNIs for network segmentation
LNI_DHCP_ENABLED=true              # Use DHCP (recommended)
LNI_STATIC_IPS="192.168.1.100,192.168.1.101"  # Optional static IPs
```

### Benefits
- **Direct On-Premises Access**: VMs bypass VPC networking for local connectivity
- **Network Segmentation**: Each LNI provides isolated network path for workloads  
- **Bandwidth Scaling**: Multiple 10Gbps interfaces for high-throughput workloads
- **Dedicated IPs**: Each VM/container gets own on-premises IP address

### VM Network Architecture
- **ENI (eth0)**: Management network for SSH/Cockpit access
- **LNI1 (eth1)**: Default VM network + backup SSH/HTTP access  
- **LNI2+ (eth2+)**: Additional isolated networks for workload segmentation
- **Libvirt Bridges**: Each LNI mapped to br-lni1, br-lni2, etc. for VM assignment

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