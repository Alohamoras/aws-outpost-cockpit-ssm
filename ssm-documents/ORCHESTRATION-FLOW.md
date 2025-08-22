# SSM Document Orchestration Flow

## ✅ **Fixed Orchestration Issues**

The following critical issues were identified and corrected:

### **Issues Found:**
1. **Missing nextStep connections** - Components weren't chaining to the next step on success
2. **User-data bootstrap redundancy** - Bootstrap script was trying to trigger SSM automation (should be handled by launch script)
3. **Incomplete parameter passing** - Some .env variables weren't being passed through

### **Issues Fixed:**
1. ✅ Added `nextStep` properties to all main components
2. ✅ Fixed user-data-bootstrap.sh to only prepare instance for SSM
3. ✅ Updated launch script to properly pass .env parameters

## **Corrected Flow Diagram**

```
START
  ↓
ValidateInstance
  ↓
CheckInstanceRunning
  ↓ (if running)
NotifyStart
  ↓
SystemPreparation → (success) → CoreCockpitInstall
  ↓ (failure)                      ↓ (success)
HandleSystemPrepFailure          ExtendedServicesSetup
  ↓                                ↓ (success)
END                              ThirdPartyExtensions
                                   ↓ (success)
                                 UserConfiguration
                                   ↓ (success)
                                 FinalConfiguration
                                   ↓
                                 END
```

## **Component Execution Order**

1. **SystemPreparation** (Critical)
   - Document: `cockpit-system-prep`
   - Next: `CoreCockpitInstall`
   - On Failure: `HandleSystemPrepFailure` → END

2. **CoreCockpitInstall** (Critical)
   - Document: `cockpit-core-install`
   - Next: `ExtendedServicesSetup`
   - On Failure: `HandleCoreInstallFailure` → END

3. **ExtendedServicesSetup** (Non-Critical)
   - Document: `cockpit-services-setup`
   - Next: `ThirdPartyExtensions`
   - On Failure: Check `ContinueOnError`
     - True → Continue to `ThirdPartyExtensions`
     - False → `ServicesFailureStop` → END

4. **ThirdPartyExtensions** (Non-Critical)
   - Document: `cockpit-extensions`
   - Next: `UserConfiguration`
   - On Failure: Check `ContinueOnError`
     - True → Continue to `UserConfiguration`
     - False → `ExtensionsFailureStop` → END

5. **UserConfiguration** (Non-Critical)
   - Document: `cockpit-user-config`
   - Next: `FinalConfiguration`
   - On Failure: Check `ContinueOnError`
     - True → Continue to `FinalConfiguration`
     - False → `UserConfigFailureStop` → END

6. **FinalConfiguration** (Non-Critical)
   - Document: `cockpit-finalize`
   - Next: END
   - On Failure: `HandleFinalFailure` → END (with warning)

## **Parameter Flow**

All components receive these consistent parameters from the orchestration:

```yaml
Parameters:
  InstanceId: "{{ InstanceId }}"          # From launch script
  NotificationTopic: "{{ NotificationTopic }}" # From .env SNS_TOPIC_ARN
```

Main orchestration receives these parameters from launch script:
```yaml
Parameters:
  InstanceId: "$INSTANCE_ID"              # From AWS instance launch
  NotificationTopic: "$SNS_TOPIC_ARN"    # From .env file
  ContinueOnError: "$CONTINUE_ON_ERROR"  # From .env file (default: true)
  AutomationAssumeRole: "$AUTOMATION_ASSUME_ROLE" # From .env file (optional)
```

## **Bootstrap Process**

### **Updated Bootstrap Flow:**
1. **launch-cockpit-instance.sh** → Launches EC2 instance with minimal user-data
2. **user-data-bootstrap.sh** → Prepares instance (SSM agent, network check)
3. **launch-cockpit-instance.sh** → Waits for SSM readiness, then triggers automation
4. **cockpit-deploy-automation** → Orchestrates all components

### **Previous (Broken) Flow:**
- ❌ user-data-bootstrap.sh tried to trigger SSM automation itself
- ❌ No coordination between launch script and bootstrap
- ❌ Race conditions possible

## **Error Handling Strategy**

### **Critical Components** (Must succeed):
- SystemPreparation
- CoreCockpitInstall

### **Non-Critical Components** (Can fail if ContinueOnError=true):
- ExtendedServicesSetup
- ThirdPartyExtensions  
- UserConfiguration
- FinalConfiguration

### **Notification Strategy**:
- ✅ Start notification when automation begins
- 📧 Component-level notifications from each document
- ❌ Failure notifications with specific troubleshooting guidance
- 🎉 Success notification with complete access information

## **Testing the Fixed Flow**

To verify the orchestration works correctly:

1. **Deploy documents:**
   ```bash
   ./scripts/deploy-ssm-documents.sh --test
   ```

2. **Launch instance:**
   ```bash
   ./launch-cockpit-instance.sh
   ```

3. **Monitor execution:**
   - Check SNS notifications for progress
   - Monitor SSM execution in AWS Console
   - Verify each component completes in sequence

4. **Verify logs on instance:**
   ```bash
   ssh -i ryanfill.pem rocky@$PUBLIC_IP
   sudo tail -f /var/log/cockpit-*.log
   ```

## **Rollback Strategy**

If issues occur:

1. **Individual component retry:**
   ```bash
   aws ssm send-command --document-name "cockpit-core-install" --instance-ids "$INSTANCE_ID"
   ```

2. **Partial re-run from specific component:**
   ```bash
   aws ssm start-automation-execution --document-name "cockpit-deploy-automation" \
     --parameters "InstanceId=$INSTANCE_ID,NotificationTopic=$SNS_TOPIC_ARN"
   ```

3. **Full rollback to legacy approach:**
   - Set `SSM_MAIN_DOCUMENT=cockpit-base-install` in .env
   - Use legacy user-data script

The orchestration is now properly configured to execute components in sequence with appropriate error handling and parameter passing.