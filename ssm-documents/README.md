# SSM Documents for Cockpit Installation

This directory contains modular AWS Systems Manager (SSM) documents that replace the legacy monolithic user-data script for Cockpit installation.

## Architecture Overview

The installation is broken down into manageable, reusable components that can be executed independently or as part of the main orchestration:

```
cockpit-deploy-automation (Main Orchestrator)
├── cockpit-system-prep (System preparation)
├── cockpit-core-install (Core Cockpit installation)
├── cockpit-services-setup (Extended services)
├── cockpit-extensions (Third-party modules)
├── cockpit-user-config (User configuration)
└── cockpit-finalize (Final configuration & notification)
```

## Document Descriptions

### 1. cockpit-system-prep.yaml
**Purpose**: System preparation and dependency installation
- Network readiness validation with Outpost-aware delays
- System package updates with retry logic
- EPEL repository installation
- AWS CLI and SSM Agent setup
- Foundation for all subsequent components

**Critical**: Yes - Failure stops deployment
**Estimated Time**: 5-15 minutes (longer on Outpost)

### 2. cockpit-core-install.yaml
**Purpose**: Core Cockpit installation and basic modules
- Core Cockpit packages (cockpit, cockpit-system, cockpit-ws, cockpit-bridge)
- Basic modules (networkmanager, storaged, packagekit, sosreport)
- Service enablement and basic firewall configuration
- Web interface verification

**Critical**: Yes - Failure stops deployment
**Estimated Time**: 3-5 minutes

### 3. cockpit-services-setup.yaml
**Purpose**: Extended services for virtualization, containers, and monitoring
- Virtualization stack (libvirt, qemu-kvm, cockpit-machines)
- Container runtime (Podman, cockpit-podman)
- Performance monitoring (PCP, cockpit-pcp)
- Service configuration and user group management

**Critical**: No - Can be skipped if ContinueOnError is enabled
**Estimated Time**: 5-10 minutes

### 4. cockpit-extensions.yaml
**Purpose**: Third-party extensions and hardware-specific configuration
- 45Drives modules (file-sharing, navigator, sensors)
- Hardware sensor detection for bare metal instances
- Instance type-aware configuration
- Extension verification

**Critical**: No - Can be skipped if ContinueOnError is enabled
**Estimated Time**: 3-7 minutes

### 5. cockpit-user-config.yaml
**Purpose**: User account and security configuration
- Admin user creation with secure defaults
- Rocky/ec2-user configuration
- Sudo access configuration
- User group membership management

**Critical**: No - Can be skipped if ContinueOnError is enabled
**Estimated Time**: 1-2 minutes

### 6. cockpit-finalize.yaml
**Purpose**: Final configuration and completion notification
- Cockpit configuration files
- Welcome message creation
- Comprehensive status verification
- Final success/failure notification with complete details

**Critical**: No - Deployment completes even if this fails
**Estimated Time**: 1-2 minutes

### 7. cockpit-deploy-automation.yaml
**Purpose**: Main orchestration document
- Instance validation and state checking
- Sequential component execution with error handling
- Notification management throughout deployment
- Failure recovery and continuation logic
- Comprehensive progress reporting

**Type**: Automation (not Command like the others)
**Estimated Total Time**: 20-45 minutes

## Deployment

### Prerequisites
1. AWS CLI installed and configured
2. Appropriate IAM permissions for SSM document management
3. SNS topic created for notifications (optional but recommended)

### Deploy All Documents
```bash
./scripts/deploy-ssm-documents.sh
```

### Deploy with Options
```bash
# Deploy to specific region
./scripts/deploy-ssm-documents.sh --region us-west-2

# Deploy and cleanup old versions
./scripts/deploy-ssm-documents.sh --cleanup

# Deploy and test
./scripts/deploy-ssm-documents.sh --test

# Just list current documents
./scripts/deploy-ssm-documents.sh --list
```

## Usage

### Full Automated Deployment
```bash
aws ssm start-automation-execution \
    --document-name "cockpit-deploy-automation" \
    --parameters "InstanceId=i-1234567890abcdef0,NotificationTopic=arn:aws:sns:us-east-1:123456789012:cockpit-notifications"
```

### Individual Component Execution
```bash
# Run just system preparation
aws ssm send-command \
    --document-name "cockpit-system-prep" \
    --instance-ids "i-1234567890abcdef0" \
    --parameters "NotificationTopic=arn:aws:sns:us-east-1:123456789012:topic"

# Run just core installation (after system prep)
aws ssm send-command \
    --document-name "cockpit-core-install" \
    --instance-ids "i-1234567890abcdef0"
```

## Error Handling and Recovery

### ContinueOnError Parameter
The main orchestration document supports a `ContinueOnError` parameter (default: true):
- `true`: Non-critical component failures won't stop deployment
- `false`: Any component failure stops the entire deployment

### Individual Component Retry
If a component fails, you can retry just that component:
```bash
aws ssm send-command \
    --document-name "cockpit-services-setup" \
    --instance-ids "i-1234567890abcdef0" \
    --parameters "NotificationTopic=arn:aws:sns:us-east-1:123456789012:topic"
```

### Log Files
Each component creates its own log file on the target instance:
- `/var/log/cockpit-system-prep.log`
- `/var/log/cockpit-core-install.log`
- `/var/log/cockpit-services-setup.log`
- `/var/log/cockpit-extensions.log`
- `/var/log/cockpit-user-config.log`
- `/var/log/cockpit-finalize.log`

## Benefits of Modular Design

### Reliability
- Individual component failures don't necessarily break entire deployment
- Granular retry capabilities for failed components
- Better error isolation and diagnosis

### Reusability
- Components can be used independently for maintenance
- Easy to add new features as separate documents
- Support for different deployment scenarios

### Maintainability
- Smaller, focused documents are easier to understand and modify
- Independent testing of individual components
- Cleaner separation of concerns

### Monitoring
- Individual component progress tracking
- Detailed notifications for each phase
- Better visibility into deployment status

## Integration with Launch Script

The main `launch-cockpit-instance.sh` script has been updated to use the new orchestration:

```bash
# Old approach (deprecated)
SSM_MAIN_DOCUMENT="${SSM_MAIN_DOCUMENT:-cockpit-base-install}"

# New modular approach
SSM_MAIN_DOCUMENT="${SSM_MAIN_DOCUMENT:-cockpit-deploy-automation}"
```

This maintains backward compatibility while providing the benefits of the modular architecture.