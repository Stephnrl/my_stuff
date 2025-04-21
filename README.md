# GitHub Enterprise Server Upgrade Strategy

This document outlines the automated upgrade strategy for GitHub Enterprise Server (GHES) using Ansible, following GitHub's recommended best practices.

## Overview

This Ansible automation handles the careful step-by-step upgrade of GitHub Enterprise Server instances, with special attention to:

1. Native MySQL database protection
2. GitHub Actions runner compatibility
3. Appropriate waiting periods between upgrades
4. Comprehensive backup and snapshot strategy

## GitHub's Upgrade Recommendations

GitHub recommends the following best practices for GHES upgrades:

- **Step-by-step upgrades**: Cannot skip more than two feature releases at a time
- **Minimum 24-hour waiting period** between feature upgrades
- **Sufficient disk space**: At least 15% free space on data disk
- **Database protection**: Special care for native MySQL databases
- **Snapshots and backups**: VM snapshots and backups before upgrades
- **Runner updates**: Self-hosted GitHub Actions runners must be updated to minimum versions
- **Maintenance windows**: Plan for appropriate downtime

## Upgrade Matrix Approach

Our automation uses a version matrix to define upgrade paths:

```yaml
version_paths:
  "3.11.2":
    next_version: "3.13.14"
    package_url: "https://github-enterprise.s3.amazonaws.com/azure/updates/github-enterprise-azure-3.13.14.pkg"
    min_runner_version: "2.314.1"
  
  "3.13.14":
    next_version: "3.15.6"
    package_url: "https://github-enterprise.s3.amazonaws.com/azure/updates/github-enterprise-azure-3.15.6.pkg"
    min_runner_version: "2.319.1"
    
  "3.15.6":
    next_version: "3.16.2"
    package_url: "https://github-enterprise.s3.amazonaws.com/azure/updates/github-enterprise-azure-3.16.2.pkg"
    min_runner_version: "2.321.0"
```

## Upgrade Process Flow

The automated process follows these steps for each upgrade:

1. **Pre-upgrade verification**
   - Confirm current version
   - Verify sufficient disk space (≥15% free)
   - Check MySQL database health

2. **Runner updates**
   - Update self-hosted GitHub Actions runners to minimum required version

3. **Backup & snapshot**
   - Create backup using GitHub Backup Utilities
   - Take VM snapshot of instance
   - Enable maintenance mode

4. **Upgrade execution**
   - Download upgrade package
   - Apply upgrade package
   - Wait for background migrations to complete

5. **Post-upgrade verification**
   - Verify MySQL database health
   - Check that upgrade was successful
   - Disable maintenance mode

6. **Wait period**
   - Wait 24 hours between feature upgrades
   - Allow background migrations to complete
   - Verify system stability

## Self-hosted Runner Version Requirements

GitHub Enterprise Server requires specific minimum versions of the Actions runner:

| GHES Version | Minimum Runner Version |
|--------------|------------------------|
| 3.16.x       | 2.321.0                |
| 3.15.x       | 2.319.1                |
| 3.14.x       | 2.317.0                |
| 3.13.x       | 2.314.1                |
| 3.12.x       | 2.311.0                |
| 3.11.x       | 2.309.0                |

## MySQL Database Considerations

Special considerations for native MySQL database:

- Pre and post-upgrade database health checks
- Wait for all background migrations to complete
- Enable maintenance mode to prevent database corruption
- Take snapshots before touching the database

## Usage

1. Update the `upgrade_matrix.yml` file with your current and target versions
2. Set the starting version in the playbook:
   ```bash
   ansible-playbook ghe_upgrade_orchestration.yml -e "current_version=3.11.2"
   ```
3. Follow the prompts for each upgrade step, respecting the 24-hour waiting periods

## Monitoring and Troubleshooting

- Monitor background jobs with `ghe-check-background-upgrade-jobs`
- Check MySQL status with `ghe-mysql-check`
- Review logs in `/var/log/github/` after upgrade
- Verify successful upgrade with version check and functionality testing

## Rollback Procedure

If an upgrade fails:

1. Enter maintenance mode: `ghe-maintenance -s`
2. Restore from VM snapshot
3. Apply the backup if necessary: `ghe-restore`
4. Disable maintenance mode: `ghe-maintenance -u`

---

*This automation strategy follows GitHub's documented best practices for enterprise upgrades while adding additional safeguards for database protection.*
