# Legacy Scripts

This directory contains scripts from the original monolithic architecture that were used before the self-contained user-data architecture.

## Remaining Files

- `manage-instances.sh` - Instance management and monitoring utility (still actively used)
- `README.md` - This documentation file

## Removed Files (Successfully Migrated)

The following files have been successfully migrated to the self-contained user-data architecture and removed:
- ~~`configure-storage.sh`~~ - Unused storage configuration script
- ~~`launch-cockpit-instance.sh`~~ - Original monolithic launch script (replaced by main launch script)
- ~~`user-data.sh`~~ - Original 427-line user-data script (replaced by complete bootstrap script)

## Current Status

- **`manage-instances.sh`**: Still actively used for instance operations (status, SSH, logs, etc.)
- **Monolithic scripts**: Successfully replaced by self-contained user-data architecture
- **Migration**: Complete - all functionality preserved in streamlined bootstrap approach

## Current Architecture

The original monolithic approach has been replaced with:
- Main launcher: `launch-cockpit-instance.sh`
- Complete bootstrap: `user-data-bootstrap.sh` - All installation during instance launch
- No external dependencies: Everything self-contained in user-data script
- Components: Network readiness, system updates, SSM agent, complete Cockpit installation