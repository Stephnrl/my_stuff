# src/bootstrap/github_backup_deploy.py
"""
GitHub Backup Utils deployment and management module
"""

import os
import json
import hashlib
from typing import Dict, Optional, Tuple
from dataclasses import dataclass
from src.utils.logger import setup_logger

@dataclass
class BackupConfig:
    """Configuration for GitHub Backup Utils"""
    backup_user: str = "git-backup"
    backup_group: str = "git-backup"
    backup_home: str = "/home/git-backup"
    backup_data_dir: str = "/mnt/github-backup"
    github_hostname: str = ""
    github_token: str = ""
    version: str = "latest"
    
class GitHubBackupDeployer:
    """Deploy and manage GitHub Backup Utils"""
    
    GITHUB_API_URL = "https://api.github.com/repos/github/backup-utils/releases"
    
    def __init__(self, ssh_client, config: Optional[BackupConfig] = None):
        self.ssh = ssh_client
        self.logger = setup_logger(__name__)
        self.config = config or BackupConfig()
        
    def get_latest_release(self) -> Dict[str, str]:
        """Get latest release information from GitHub"""
        self.logger.info("Fetching latest GitHub Backup Utils release")
        
        # Use curl to get release info
        cmd = f"curl -s {self.GITHUB_API_URL}/latest"
        output, _, exit_code = self.ssh.execute_command(cmd)
        
        if exit_code != 0:
            raise RuntimeError("Failed to fetch release information")
        
        try:
            release_data = json.loads(output)
            version = release_data['tag_name']
            
            # Find the tarball URL
            download_url = None
            for asset in release_data.get('assets', []):
                if asset['name'].endswith('.tar.gz'):
                    download_url = asset['browser_download_url']
                    break
            
            if not download_url:
                # Use tarball URL if no assets
                download_url = release_data['tarball_url']
            
            return {
                'version': version,
                'url': download_url,
                'name': release_data['name']
            }
        except Exception as e:
            self.logger.error(f"Failed to parse release data: {e}")
            raise
    
    def check_existing_installation(self) -> Optional[str]:
        """Check if backup-utils is already installed"""
        self.logger.info("Checking for existing installation")
        
        # Check if backup-utils exists
        output, _, exit_code = self.ssh.execute_command(
            f"test -d {self.config.backup_home}/backup-utils && echo 'exists'"
        )
        
        if exit_code == 0 and 'exists' in output:
            # Get version if possible
            version_cmd = f"cd {self.config.backup_home}/backup-utils && git describe --tags 2>/dev/null || echo 'unknown'"
            version_output, _, _ = self.ssh.execute_command(version_cmd)
            return version_output.strip()
        
        return None
    
    def create_backup_user(self) -> bool:
        """Create dedicated backup user"""
        self.logger.info(f"Creating backup user: {self.config.backup_user}")
        
        try:
            # Check if user exists
            output, _, exit_code = self.ssh.execute_command(
                f"id {self.config.backup_user} 2>/dev/null"
            )
            
            if exit_code == 0:
                self.logger.info(f"User {self.config.backup_user} already exists")
                return True
            
            # Create group
            self.ssh.execute_command(
                f"sudo groupadd -r {self.config.backup_group} 2>/dev/null || true"
            )
            
            # Create user with home directory
            create_user_cmd = (
                f"sudo useradd -r -m -d {self.config.backup_home} "
                f"-g {self.config.backup_group} -s /bin/bash "
                f"-c 'GitHub Backup Service' {self.config.backup_user}"
            )
            
            output, error, exit_code = self.ssh.execute_command(create_user_cmd)
            if exit_code != 0:
                self.logger.error(f"Failed to create user: {error}")
                return False
            
            # Set up directory permissions
            self.ssh.execute_command(
                f"sudo chown -R {self.config.backup_user}:{self.config.backup_group} {self.config.backup_home}"
            )
            
            # Create .ssh directory
            self.ssh.execute_command(
                f"sudo -u {self.config.backup_user} mkdir -p {self.config.backup_home}/.ssh"
            )
            self.ssh.execute_command(
                f"sudo chmod 700 {self.config.backup_home}/.ssh"
            )
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error creating backup user: {e}")
            return False
    
    def generate_ssh_keys(self, regenerate: bool = False) -> Dict[str, str]:
        """Generate SSH keys for backup user"""
        self.logger.info("Generating SSH keys for backup user")
        
        ssh_key_path = f"{self.config.backup_home}/.ssh/id_ed25519"
        
        try:
            # Check if keys already exist
            output, _, exit_code = self.ssh.execute_command(
                f"sudo test -f {ssh_key_path} && echo 'exists'"
            )
            
            if exit_code == 0 and 'exists' in output and not regenerate:
                self.logger.info("SSH keys already exist, skipping generation")
                # Read existing public key
                pub_key, _, _ = self.ssh.execute_command(
                    f"sudo cat {ssh_key_path}.pub"
                )
                return {
                    'private_key_path': ssh_key_path,
                    'public_key': pub_key.strip()
                }
            
            # Generate new SSH key
            keygen_cmd = (
                f"sudo -u {self.config.backup_user} ssh-keygen -t ed25519 "
                f"-f {ssh_key_path} -N '' -C 'github-backup@{self.config.github_hostname}'"
            )
            
            output, error, exit_code = self.ssh.execute_command(keygen_cmd)
            if exit_code != 0:
                self.logger.error(f"Failed to generate SSH key: {error}")
                raise RuntimeError("SSH key generation failed")
            
            # Set proper permissions
            self.ssh.execute_command(f"sudo chmod 600 {ssh_key_path}")
            self.ssh.execute_command(f"sudo chmod 644 {ssh_key_path}.pub")
            
            # Read public key
            pub_key, _, _ = self.ssh.execute_command(f"sudo cat {ssh_key_path}.pub")
            
            return {
                'private_key_path': ssh_key_path,
                'public_key': pub_key.strip()
            }
            
        except Exception as e:
            self.logger.error(f"Error generating SSH keys: {e}")
            raise
    
    def download_and_extract(self, version: Optional[str] = None) -> bool:
        """Download and extract GitHub Backup Utils"""
        try:
            # Get release info
            if version == 'latest' or version is None:
                release_info = self.get_latest_release()
                version = release_info['version']
                download_url = release_info['url']
            else:
                # Construct URL for specific version
                download_url = f"https://github.com/github/backup-utils/archive/refs/tags/{version}.tar.gz"
            
            self.logger.info(f"Downloading version {version}")
            
            # Download to temporary location
            temp_file = f"/tmp/backup-utils-{version}.tar.gz"
            download_cmd = f"sudo -u {self.config.backup_user} curl -L -o {temp_file} {download_url}"
            
            output, error, exit_code = self.ssh.execute_command(download_cmd)
            if exit_code != 0:
                self.logger.error(f"Download failed: {error}")
                return False
            
            # Verify download (check file size)
            size_output, _, _ = self.ssh.execute_command(f"stat -c%s {temp_file}")
            file_size = int(size_output.strip())
            if file_size < 1000:  # Less than 1KB indicates download failure
                self.logger.error("Downloaded file is too small, download may have failed")
                return False
            
            # Calculate checksum for verification
            checksum_output, _, _ = self.ssh.execute_command(f"sha256sum {temp_file} | cut -d' ' -f1")
            self.logger.info(f"Download checksum: {checksum_output.strip()}")
            
            # Extract
            extract_dir = f"{self.config.backup_home}/backup-utils"
            
            # Remove old installation if exists
            self.ssh.execute_command(f"sudo rm -rf {extract_dir}.old")
            self.ssh.execute_command(f"sudo mv {extract_dir} {extract_dir}.old 2>/dev/null || true")
            
            # Create directory and extract
            self.ssh.execute_command(f"sudo mkdir -p {extract_dir}")
            extract_cmd = f"sudo tar -xzf {temp_file} -C {extract_dir} --strip-components=1"
            
            output, error, exit_code = self.ssh.execute_command(extract_cmd)
            if exit_code != 0:
                self.logger.error(f"Extraction failed: {error}")
                # Restore old version if extract failed
                self.ssh.execute_command(f"sudo mv {extract_dir}.old {extract_dir} 2>/dev/null || true")
                return False
            
            # Set ownership
            self.ssh.execute_command(
                f"sudo chown -R {self.config.backup_user}:{self.config.backup_group} {extract_dir}"
            )
            
            # Clean up
            self.ssh.execute_command(f"sudo rm -f {temp_file}")
            self.ssh.execute_command(f"sudo rm -rf {extract_dir}.old")
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error downloading/extracting: {e}")
            return False
    
    def configure_backup_utils(self, github_hostname: str, github_token: Optional[str] = None) -> bool:
        """Configure backup-utils with GitHub connection details"""
        self.logger.info("Configuring backup-utils")
        
        try:
            config_file = f"{self.config.backup_home}/backup-utils/backup.config"
            
            # Create configuration
            config_content = f"""# GitHub Backup Utils Configuration
# Generated by automated deployment

# GitHub hostname
GHE_HOSTNAME="{github_hostname}"

# Backup data directory
GHE_DATA_DIR="{self.config.backup_data_dir}/data"

# Number of backup snapshots to retain
GHE_NUM_SNAPSHOTS=10

# Backup user
GHE_BACKUP_USER="git"

# Extra options
GHE_EXTRA_SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

# Verbose output
GHE_VERBOSE=1

# Create backup directory structure
GHE_CREATE_DATA_DIR=yes
"""
            
            # If using GitHub.com (not Enterprise), add token
            if github_token and 'github.com' in github_hostname:
                config_content += f'\n# GitHub API token for github.com\nGITHUB_TOKEN="{github_token}"\n'
            
            # Write configuration
            write_config_cmd = f"echo '{config_content}' | sudo tee {config_file}"
            output, error, exit_code = self.ssh.execute_command(write_config_cmd)
            
            if exit_code != 0:
                self.logger.error(f"Failed to write configuration: {error}")
                return False
            
            # Set proper permissions
            self.ssh.execute_command(
                f"sudo chown {self.config.backup_user}:{self.config.backup_group} {config_file}"
            )
            self.ssh.execute_command(f"sudo chmod 600 {config_file}")
            
            # Create data directories
            data_dirs = [
                f"{self.config.backup_data_dir}/data",
                f"{self.config.backup_data_dir}/data/current",
                f"{self.config.backup_data_dir}/logs"
            ]
            
            for dir_path in data_dirs:
                self.ssh.execute_command(f"sudo mkdir -p {dir_path}")
                self.ssh.execute_command(
                    f"sudo chown {self.config.backup_user}:{self.config.backup_group} {dir_path}"
                )
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error configuring backup-utils: {e}")
            return False
    
    def setup_cron_job(self, schedule: str = "0 */4 * * *") -> bool:
        """Set up cron job for automated backups"""
        self.logger.info("Setting up cron job for automated backups")
        
        try:
            backup_script = f"{self.config.backup_home}/run-backup.sh"
            
            # Create backup script
            script_content = f"""#!/bin/bash
# GitHub Backup Script
# Generated by automated deployment

export PATH=/usr/local/bin:/usr/bin:/bin
export HOME={self.config.backup_home}

BACKUP_UTILS_DIR="{self.config.backup_home}/backup-utils"
LOG_FILE="{self.config.backup_data_dir}/logs/backup-$(date +%Y%m%d-%H%M%S).log"

echo "Starting backup at $(date)" >> "$LOG_FILE"

cd "$BACKUP_UTILS_DIR"
./bin/ghe-backup >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "Backup completed successfully at $(date)" >> "$LOG_FILE"
else
    echo "Backup failed at $(date)" >> "$LOG_FILE"
fi

# Keep only last 30 log files
find {self.config.backup_data_dir}/logs -name "backup-*.log" -type f -mtime +30 -delete
"""
            
            # Write script
            write_script_cmd = f"echo '{script_content}' | sudo tee {backup_script}"
            self.ssh.execute_command(write_script_cmd)
            
            # Make executable
            self.ssh.execute_command(f"sudo chmod +x {backup_script}")
            self.ssh.execute_command(
                f"sudo chown {self.config.backup_user}:{self.config.backup_group} {backup_script}"
            )
            
            # Set up cron job
            cron_entry = f'{schedule} {self.config.backup_user} {backup_script}'
            cron_file = f"/etc/cron.d/github-backup"
            
            cron_content = f"""# GitHub Backup Utils Cron Job
# Generated by automated deployment
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin

{cron_entry}
"""
            
            write_cron_cmd = f"echo '{cron_content}' | sudo tee {cron_file}"
            self.ssh.execute_command(write_cron_cmd)
            self.ssh.execute_command(f"sudo chmod 644 {cron_file}")
            
            # Restart cron to pick up new job
            self.ssh.execute_command("sudo systemctl restart cron 2>/dev/null || sudo service cron restart")
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error setting up cron job: {e}")
            return False
    
    def test_backup_connection(self) -> bool:
        """Test connection to GitHub instance"""
        self.logger.info("Testing backup connection")
        
        try:
            test_cmd = (
                f"sudo -u {self.config.backup_user} "
                f"{self.config.backup_home}/backup-utils/bin/ghe-host-check"
            )
            
            output, error, exit_code = self.ssh.execute_command(test_cmd)
            
            if exit_code == 0:
                self.logger.info("Connection test successful")
                return True
            else:
                self.logger.error(f"Connection test failed: {error}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error testing connection: {e}")
            return False
    
    def deploy(self, github_hostname: str, github_token: Optional[str] = None, 
               version: str = "latest") -> Dict[str, any]:
        """Full deployment process"""
        self.logger.info("Starting GitHub Backup Utils deployment")
        
        results = {
            'success': True,
            'version': version,
            'ssh_public_key': None,
            'errors': []
        }
        
        try:
            # Check existing installation
            existing_version = self.check_existing_installation()
            if existing_version:
                self.logger.info(f"Found existing installation: {existing_version}")
            
            # Create backup user
            if not self.create_backup_user():
                results['errors'].append("Failed to create backup user")
                results['success'] = False
                return results
            
            # Generate SSH keys
            ssh_keys = self.generate_ssh_keys()
            results['ssh_public_key'] = ssh_keys['public_key']
            
            # Download and extract
            if not self.download_and_extract(version):
                results['errors'].append("Failed to download/extract backup-utils")
                results['success'] = False
                return results
            
            # Configure
            if not self.configure_backup_utils(github_hostname, github_token):
                results['errors'].append("Failed to configure backup-utils")
                results['success'] = False
                return results
            
            # Set up cron job
            if not self.setup_cron_job():
                results['errors'].append("Failed to set up cron job")
                # Not fatal, continue
            
            # Get actual version installed
            version_cmd = f"cd {self.config.backup_home}/backup-utils && git describe --tags 2>/dev/null || echo '{version}'"
            installed_version, _, _ = self.ssh.execute_command(version_cmd)
            results['version'] = installed_version.strip()
            
            self.logger.info("Deployment completed successfully")
            
        except Exception as e:
            results['success'] = False
            results['errors'].append(str(e))
            self.logger.error(f"Deployment failed: {e}")
        
        return results
    
    def upgrade(self, version: str = "latest") -> bool:
        """Upgrade existing installation"""
        self.logger.info(f"Upgrading GitHub Backup Utils to {version}")
        
        try:
            # Check existing installation
            existing_version = self.check_existing_installation()
            if not existing_version:
                self.logger.error("No existing installation found")
                return False
            
            self.logger.info(f"Current version: {existing_version}")
            
            # Download and extract new version
            if not self.download_and_extract(version):
                self.logger.error("Upgrade failed during download/extract")
                return False
            
            # Test the new installation
            if not self.test_backup_connection():
                self.logger.warning("Connection test failed after upgrade")
            
            self.logger.info("Upgrade completed successfully")
            return True
            
        except Exception as e:
            self.logger.error(f"Upgrade failed: {e}")
            return False
