# Legacy SSM Documents

This directory contains the previous complex modular architecture that has been replaced with a simplified single-document approach.

## Replaced Architecture

The following files were part of the complex modular SSM architecture:

- `legacy-cockpit-deploy-automation.yaml` - Main orchestration document (7 steps)
- `legacy-cockpit-deploy-automation.json` - JSON version of orchestration
- `legacy-cockpit-system-prep.yaml` - System preparation component
- `legacy-cockpit-core-install.yaml` - Core Cockpit installation component
- `legacy-cockpit-services-setup.yaml` - Extended services component
- `legacy-cockpit-extensions.yaml` - Third-party extensions component
- `legacy-cockpit-user-config.yaml` - User configuration component
- `legacy-cockpit-finalize.yaml` - Final configuration component

## Issues with Previous Architecture

1. **Complexity**: 7 separate documents (1,282 lines total)
2. **Parameter passing issues**: SSM automation parameter substitution failures
3. **Orchestration problems**: aws:runDocument vs aws:runCommand confusion
4. **Hard to debug**: Multiple execution logs across different documents
5. **JSON/YAML format issues**: Automation documents required JSON conversion

## Current Simplified Architecture

**Single Document**: `cockpit-complete-install.yaml` (~800 lines)
- All components in logical sections within one document
- Direct parameter substitution works reliably
- Single execution log for easy debugging
- Simple `aws ssm send-command` execution
- No orchestration complexity

## Migration Benefits

- **90% complexity reduction** (7 documents → 1 document)
- **Reliable SNS notifications** (direct parameter substitution)
- **Easier debugging** (single log file)
- **Faster execution** (no automation overhead)
- **Simpler monitoring** (single command status vs multiple step tracking)

The simplified architecture achieves the same functionality with dramatically reduced complexity.