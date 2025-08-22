# Legacy Scripts

This directory contains scripts from the original monolithic architecture that were used before the SSM architecture overhaul.

## Remaining Files

- `manage-instances.sh` - Instance management and monitoring utility (still actively used)
- `README.md` - This documentation file

## Removed Files (Successfully Migrated)

The following files have been successfully migrated to the new modular SSM architecture and removed:
- ~~`configure-storage.sh`~~ - Unused storage configuration script
- ~~`launch-cockpit-instance.sh`~~ - Original monolithic launch script (replaced by main launch script)
- ~~`user-data.sh`~~ - Original 427-line user-data script (replaced by modular SSM documents)

## Current Status

- **`manage-instances.sh`**: Still actively used for instance operations (status, SSH, logs, etc.)
- **Monolithic scripts**: Successfully replaced by modular SSM document architecture
- **Migration**: Complete - all functionality preserved in new modular approach

## New Architecture

The original monolithic approach has been replaced with:
- Main launcher: `launch-cockpit-instance.sh`
- Modular SSM documents in `ssm-documents/` directory
- Orchestration: `cockpit-deploy-automation.yaml`
- Individual components: System prep, core install, services, extensions, user config, finalization