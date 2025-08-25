# Architecture Guide

Technical deep-dive into the AWS Outpost Cockpit SSM deployment architecture.

## 🏗️ SSM Multi-Phase Architecture

The deployment uses AWS Systems Manager for reliable, observable deployment across 7 phases:

### Phase 1: Minimal User-Data Bootstrap
- **File**: `user-data-minimal.sh` (~40 lines vs 378 in legacy)
- **Purpose**: Network readiness validation and SSM agent setup
- **Duration**: ~5-10 minutes
- **Critical**: Must complete successfully for SSM phases to work

### Phase 2-7: SSM Document Execution
Executed sequentially by the launcher via AWS Systems Manager:

#### Phase 2: System Updates (`outpost-system-updates.json`)
- System package updates and AWS CLI verification
- Duration: ~10-15 minutes

#### Phase 3: Storage Configuration (`outpost-storage-config.json`)
- RAID5 setup for data drives (3+ drives required)
- Root OS volume extension using available space
- LVM volume creation for VMs, containers, and storage
- Duration: ~5-15 minutes
- Non-critical: Deployment continues if this fails

#### Phase 4: Core Cockpit (`outpost-cockpit-core.json`)
- Core Cockpit packages and basic configuration
- Duration: ~5-10 minutes

#### Phase 5: Cockpit Extensions (`outpost-cockpit-extensions.json`)
- Virtualization, containers, and monitoring packages
- Duration: ~15-20 minutes
- Non-critical: Deployment continues if this fails

#### Phase 6: Third-party Extensions (`outpost-cockpit-thirdparty.json`)
- 45Drives extensions for enhanced functionality
- Duration: ~5-10 minutes
- Non-critical: Deployment continues if this fails

#### Phase 7: Final Configuration (`outpost-cockpit-config.json`)
- User accounts, final settings, and verification
- Duration: ~2-5 minutes

## Key Architecture Benefits

### ✅ **Idempotent Operations**
- Safe to re-run, resumes from failure points
- Smart state detection prevents duplicate work
- Individual phase retry without full restart

### ✅ **Enhanced Observability** 
- Real-time progress via AWS console
- Phase-specific logs for targeted troubleshooting
- Built-in progress tracking and status reporting

### ✅ **Resilient Error Handling**
- Individual phase failure doesn't stop everything
- Non-critical phases can fail gracefully
- Built-in retry mechanisms and timeout handling

### ✅ **Maintainable Design**
- Separate, focused deployment phases (5 SSM documents)
- Clear separation of concerns
- Version-controlled deployment artifacts

### ✅ **AWS-Native Integration**
- Leverages SSM for enterprise-grade deployment
- Better integration with AWS monitoring and alerting
- No SSH dependencies for remote execution

## 📋 Component Details

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

## Technical Implementation

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

## State Management

### Instance State Tracking
- Instance details are stored in `.last-instance-id` after launch
- Contains instance ID, public IP, and bootstrap status for management operations

### Phase State Detection
The smart launcher can detect which phases have completed by:
- Checking SSM command history via AWS API
- Analyzing console log markers for completion status
- Validating service states and file markers on the instance

### Resume Logic
When resuming a deployment:
1. **State Analysis**: Checks AWS SSM command history for the instance
2. **Phase Detection**: Determines the last successfully completed phase
3. **Validation**: Verifies phase completion through multiple methods
4. **Smart Resume**: Continues from the next required phase
5. **Error Handling**: Can retry failed phases or skip non-critical ones

## File Structure Details

```
ssm-documents/
├── outpost-system-updates.json      # Phase 2: System updates and AWS CLI
├── outpost-storage-config.json      # Phase 3: RAID5 and storage optimization
├── outpost-cockpit-core.json        # Phase 4: Core Cockpit installation
├── outpost-cockpit-extensions.json  # Phase 5: Virtualization and containers
├── outpost-cockpit-thirdparty.json  # Phase 6: 45Drives extensions
└── outpost-cockpit-config.json      # Phase 7: Final configuration
```

Each SSM document is a self-contained deployment phase with:
- **Input validation** for required parameters
- **Idempotent operations** that can be safely re-run
- **Comprehensive logging** to phase-specific log files
- **Error handling** with graceful degradation
- **Success markers** for state tracking

## Network Architecture

### Connectivity Requirements
- **Outbound HTTPS (443)**: For package repositories and AWS API calls
- **Outbound HTTP (80)**: For some package mirrors and redirects
- **AWS Endpoints**: Systems Manager, EC2, and S3 service endpoints
- **Package Repositories**: Rocky Linux repos, EPEL, 45Drives

### Security Model
- **Instance Profile**: Attached IAM role with SSM permissions
- **Security Groups**: Inbound rules for SSH (22) and Cockpit (9090)
- **Elastic IP**: Optional public IP assignment for external access
- **Private Subnets**: Can deploy in private subnets with NAT gateway

## Legacy Migration Notes
- Project migrated from monolithic user-data to SSM-based modular deployment
- Original 378-line bootstrap script replaced with 40-line minimal bootstrap
- All complex installation logic moved to versioned SSM documents
- Legacy utilities preserved in `legacy/` directory for reference and management operations
- Improved from single-point-of-failure to resilient multi-phase architecture

## Performance Optimizations

### AWS Outpost Specific
- **Extended Timeouts**: Network operations tuned for Outpost latency
- **Retry Logic**: Aggressive retry patterns for package operations
- **Batch Operations**: Grouped package installations to reduce round-trips
- **Parallel Execution**: Where possible, operations run concurrently

### Resource Utilization
- **Minimal Bootstrap**: Reduces initial user-data execution time
- **Phased Installation**: Spreads resource usage across multiple phases
- **Smart Dependencies**: Phases only install what's needed for their function
- **Storage Optimization**: RAID5 and LVM setup optimized for workload patterns

## Deployment Pipeline

### Pre-deployment Validation
1. **Environment Check**: Validates `.env` configuration
2. **AWS Connectivity**: Tests AWS CLI and service endpoints
3. **Resource Availability**: Checks subnet capacity and security groups
4. **SSM Document Sync**: Updates or creates required SSM documents

### Execution Flow
1. **Instance Launch**: EC2 instance with minimal user-data
2. **Bootstrap Wait**: Monitors console logs for SSM readiness
3. **Phase Execution**: Sequential SSM command execution
4. **Progress Monitoring**: Real-time status updates and error detection
5. **Completion Validation**: Verifies all critical phases completed successfully

### Post-deployment
1. **Service Validation**: Tests Cockpit web interface accessibility
2. **State Recording**: Updates `.last-instance-id` with deployment details
3. **Status Reporting**: Displays completion status and next steps