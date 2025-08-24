# AWS Outpost Cockpit - SSM Multi-Phase Architecture

This document describes the new SSM-based multi-phase architecture for deploying Cockpit on AWS Outpost instances.

## Architecture Overview

The deployment is now split into phases for better maintainability, error handling, and observability:

### Phase 1: Minimal User-Data Bootstrap
- **File**: `user-data-minimal.sh`
- **Purpose**: Network readiness validation and SSM agent setup
- **Duration**: ~5-10 minutes
- **Critical**: Must complete successfully for SSM phases to work

### Phase 2-6: SSM Document Execution
Executed sequentially by the launcher script via AWS Systems Manager:

1. **System Updates** (`outpost-system-updates.json`)
   - System package updates and AWS CLI verification
   - Duration: ~10-15 minutes

2. **Core Cockpit** (`outpost-cockpit-core.json`)
   - Core Cockpit packages and basic configuration
   - Duration: ~5-10 minutes

3. **Cockpit Extensions** (`outpost-cockpit-extensions.json`)
   - Virtualization, containers, and monitoring packages
   - Duration: ~15-20 minutes
   - Non-critical: Deployment continues if this fails

4. **Third-party Extensions** (`outpost-cockpit-thirdparty.json`)
   - 45Drives extensions for enhanced functionality
   - Duration: ~5-10 minutes
   - Non-critical: Deployment continues if this fails

5. **Final Configuration** (`outpost-cockpit-config.json`)
   - User accounts, final settings, and verification
   - Duration: ~2-5 minutes

## File Structure

```
.
├── launch-cockpit-instance-ssm.sh    # New SSM orchestrator
├── user-data-minimal.sh              # Minimal bootstrap (40 lines)
├── user-data-bootstrap.sh            # Legacy monolithic script
├── launch-cockpit-instance.sh        # Legacy launcher
├── ssm-documents/                    # SSM deployment phases
│   ├── outpost-system-updates.json
│   ├── outpost-cockpit-core.json
│   ├── outpost-cockpit-extensions.json
│   ├── outpost-cockpit-thirdparty.json
│   └── outpost-cockpit-config.json
├── .env.example                      # Environment template
├── .env                              # Local configuration
└── legacy/                           # Legacy management scripts
```

## Usage

### Quick Start
```bash
# Copy and configure environment
cp .env.example .env
# Edit .env with your settings

# Launch with new SSM architecture
./launch-cockpit-instance-ssm.sh
```

### Environment Configuration
Required in `.env`:
```bash
OUTPOST_ID=your-outpost-id
SUBNET_ID=your-subnet-id
SECURITY_GROUP_ID=your-security-group-id
KEY_NAME=your-key-name
SNS_TOPIC_ARN=your-sns-topic-arn
REGION=us-east-1
```

## Advantages of SSM Architecture

### ✅ Better Error Handling
- Each phase can fail independently with detailed error reporting
- Non-critical phases can fail without stopping deployment
- Built-in retry mechanisms and timeout handling

### ✅ Enhanced Observability
- Real-time progress monitoring through AWS console
- Detailed logs for each phase stored separately
- SNS notifications for each phase completion/failure

### ✅ Improved Maintainability
- Individual components are easier to update and test
- Clear separation of concerns
- Version-controlled SSM documents

### ✅ Better Testing
- Each phase can be tested independently
- Easier to reproduce specific installation issues
- Selective re-execution of failed phases

### ✅ AWS-Native Benefits
- Leverages AWS Systems Manager capabilities
- Better integration with AWS monitoring and alerting
- No SSH dependencies for remote execution

## Monitoring and Troubleshooting

### Real-time Monitoring
```bash
# Monitor via AWS Console
# Go to Systems Manager > Command History
# Filter by Instance ID to see all phases

# Monitor via CLI
aws ssm list-commands --region $REGION --instance-id $INSTANCE_ID
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

### Troubleshooting Failed Phases
If a phase fails, you can:
1. Check the specific phase log file
2. Re-execute just that phase via AWS console
3. Update the SSM document and retry

```bash
# Re-execute a specific phase
aws ssm send-command \
  --region $REGION \
  --document-name "outpost-cockpit-core" \
  --instance-ids $INSTANCE_ID \
  --parameters "snsTopicArn=$SNS_TOPIC_ARN,instanceId=$INSTANCE_ID"
```

## Migration from Legacy Architecture

The legacy single user-data script approach is preserved for compatibility:
- `launch-cockpit-instance.sh` - Legacy launcher
- `user-data-bootstrap.sh` - Legacy monolithic bootstrap script

### When to Use Each Architecture

**Use SSM Architecture (`launch-cockpit-instance-ssm.sh`) when:**
- You want better error handling and observability
- You need to customize specific installation phases
- You're developing or testing the deployment process
- You want to leverage AWS-native monitoring

**Use Legacy Architecture (`launch-cockpit-instance.sh`) when:**
- You prefer a simpler, self-contained approach
- You want to minimize AWS service dependencies
- You're doing quick prototyping or testing

## Performance Comparison

| Aspect | Legacy Architecture | SSM Architecture |
|--------|-------------------|------------------|
| **Total Time** | 45-60 minutes | 50-65 minutes |
| **Error Recovery** | All-or-nothing restart | Selective phase retry |
| **Observability** | Single log file | Phase-specific logs + AWS console |
| **Maintainability** | 378-line monolith | 5 focused documents |
| **Testing** | Full deployment required | Individual phase testing |
| **Debugging** | SSH required for logs | AWS console + SNS notifications |

## IAM Requirements

The SSM architecture requires additional IAM permissions:
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

The instance profile automatically includes:
- `AmazonSSMManagedInstanceCore` policy
- SNS publish permissions for notifications

## Future Enhancements

Potential improvements to the SSM architecture:
- **Parallel Execution**: Run non-dependent phases in parallel
- **Conditional Phases**: Skip phases based on instance type or configuration
- **Rollback Capability**: Automatic rollback on critical phase failures
- **Phase Dependencies**: Smart dependency management between phases
- **Custom Phases**: Easy addition of user-defined installation phases