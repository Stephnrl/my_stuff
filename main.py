#!/usr/bin/env python3
"""
SSH Client with LVM Bootstrap capability
"""
import sys
import argparse
from src.ssh_client.connection_manager import ssh_connection
from src.utils.logger import setup_logger

def run_ssh_commands(args):
    """Run standard SSH commands"""
    logger = setup_logger('ssh_commands')
    
    try:
        with ssh_connection(use_key=not args.password) as ssh:
            if args.command:
                # Execute single command
                output, error, exit_code = ssh.execute_command(args.command)
                
                if exit_code == 0:
                    print(output)
                else:
                    print(f"Error: {error}", file=sys.stderr)
                    return exit_code
            else:
                # Interactive mode - execute multiple commands
                print("Connected to remote host. Type 'exit' to quit.")
                while True:
                    try:
                        cmd = input("$ ")
                        if cmd.lower() in ['exit', 'quit']:
                            break
                        
                        output, error, exit_code = ssh.execute_command(cmd)
                        if output:
                            print(output)
                        if error:
                            print(f"Error: {error}", file=sys.stderr)
                    except KeyboardInterrupt:
                        print("\nUse 'exit' to quit")
                        continue
                    
    except Exception as e:
        logger.error(f"SSH operation failed: {e}")
        return 1
    
    return 0

def run_lvm_bootstrap(args):
    """Run LVM bootstrap process"""
    # Import here to avoid circular imports
    from src.bootstrap.lvm_bootstrap import LVMBootstrap
    
    logger = setup_logger('lvm_bootstrap_main')
    
    try:
        with ssh_connection(use_key=not args.password) as ssh:
            bootstrap = LVMBootstrap(ssh)
            
            # If check-only mode
            if args.check_only:
                logger.info(f"Checking disk status for {args.device}")
                status = bootstrap.check_disk_availability(args.device)
                disk_info = bootstrap.get_disk_info(args.device)
                
                print(f"\nDisk: {args.device}")
                print(f"Status: {status.value}")
                print(f"Size: {disk_info.size}")
                print(f"Mounted: {disk_info.mountpoint or 'No'}")
                print(f"Filesystem: {disk_info.fstype or 'None'}")
                print(f"Partitions: {', '.join(disk_info.partitions) or 'None'}")
                return 0
            
            # Confirm before proceeding
            if not args.yes:
                print(f"\nThis will bootstrap LVM on {args.device}")
                print(f"Volume Group: {args.vg_name}")
                print(f"Logical Volume: {args.lv_name}")
                print(f"Mount Point: {args.mount_point}")
                print("\nWARNING: This will destroy all data on the disk!")
                
                response = input("\nContinue? (yes/no): ")
                if response.lower() != 'yes':
                    print("Bootstrap cancelled")
                    return 0
            
            # Run bootstrap
            success = bootstrap.bootstrap_disk(
                device=args.device,
                mount_point=args.mount_point,
                vg_name=args.vg_name,
                lv_name=args.lv_name
            )
            
            if success:
                print("\n✅ Bootstrap completed successfully!")
                print(f"Your disk is mounted at: {args.mount_point}")
            else:
                print("\n❌ Bootstrap failed! Check logs for details.")
                return 1
                
    except Exception as e:
        logger.error(f"Bootstrap operation failed: {e}")
        return 1
    
    return 0

def run_github_backup_deploy(args):
    """Deploy GitHub Backup Utils"""
    from src.bootstrap.github_backup_deploy import GitHubBackupDeployer, BackupConfig
    
    logger = setup_logger('github_backup_deploy')
    
    try:
        with ssh_connection(use_key=not args.password) as ssh:
            # Create config
            config = BackupConfig(
                backup_user=args.backup_user,
                backup_home=args.backup_home,
                backup_data_dir=args.data_dir
            )
            
            deployer = GitHubBackupDeployer(ssh, config)
            
            # Handle upgrade mode
            if args.upgrade:
                logger.info("Running upgrade mode")
                success = deployer.upgrade(args.version)
                if success:
                    print("\n✅ Upgrade completed successfully!")
                else:
                    print("\n❌ Upgrade failed! Check logs for details.")
                    return 1
                return 0
            
            # Check for existing installation
            existing = deployer.check_existing_installation()
            if existing and not args.force:
                print(f"\n⚠️  Existing installation found: {existing}")
                print("Use --force to overwrite or --upgrade to upgrade")
                return 1
            
            # Run deployment
            print("\n🚀 Starting GitHub Backup Utils deployment")
            print(f"Target host: {args.github_host}")
            print(f"Backup user: {config.backup_user}")
            print(f"Data directory: {config.backup_data_dir}")
            
            if not args.yes:
                response = input("\nContinue? (yes/no): ")
                if response.lower() != 'yes':
                    print("Deployment cancelled")
                    return 0
            
            # Deploy
            results = deployer.deploy(
                github_hostname=args.github_host,
                github_token=args.github_token,
                version=args.version
            )
            
            if results['success']:
                print("\n✅ Deployment completed successfully!")
                print(f"Version installed: {results['version']}")
                print("\n📋 Next steps:")
                print("1. Add the following SSH public key to your GitHub instance:")
                print("-" * 70)
                print(results['ssh_public_key'])
                print("-" * 70)
                print(f"\n2. For GitHub Enterprise: Add to https://{args.github_host}/setup/settings")
                print("   For GitHub.com: Add to https://github.com/settings/keys")
                print("\n3. Test the connection:")
                print(f"   python main.py test-backup --github-host {args.github_host}")
                
                # Test connection if requested
                if args.test_connection:
                    print("\n🧪 Testing connection...")
                    if deployer.test_backup_connection():
                        print("✅ Connection test successful!")
                    else:
                        print("❌ Connection test failed. Please check SSH key configuration.")
            else:
                print("\n❌ Deployment failed!")
                for error in results['errors']:
                    print(f"  - {error}")
                return 1
                
    except Exception as e:
        logger.error(f"Deployment failed: {e}")
        return 1
    
    return 0

def run_test_backup(args):
    """Test backup connection"""
    from src.bootstrap.github_backup_deploy import GitHubBackupDeployer, BackupConfig
    
    logger = setup_logger('test_backup')
    
    try:
        with ssh_connection(use_key=not args.password) as ssh:
            config = BackupConfig()
            deployer = GitHubBackupDeployer(ssh, config)
            
            # Update config if custom host provided
            if args.github_host:
                # Update the backup config file with new host
                deployer.configure_backup_utils(args.github_host)
            
            print("🧪 Testing backup connection...")
            if deployer.test_backup_connection():
                print("✅ Connection test successful!")
                
                # Run a test backup if requested
                if args.run_backup:
                    print("\n📦 Running test backup...")
                    backup_cmd = f"sudo -u {config.backup_user} {config.backup_home}/backup-utils/bin/ghe-backup"
                    output, error, exit_code = ssh.execute_command(backup_cmd)
                    
                    if exit_code == 0:
                        print("✅ Test backup completed successfully!")
                        print("Check the logs for details.")
                    else:
                        print(f"❌ Test backup failed: {error}")
                        return 1
            else:
                print("❌ Connection test failed!")
                print("Please check:")
                print("1. SSH key is added to GitHub")
                print("2. Network connectivity to GitHub")
                print("3. Backup configuration is correct")
                return 1
                
    except Exception as e:
        logger.error(f"Test failed: {e}")
        return 1
    
    return 0

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='SSH Client with LVM Bootstrap and GitHub Backup Utils')
    
    # Common arguments
    parser.add_argument('--password', action='store_true', 
                       help='Use password authentication instead of key')
    
    # Create subparsers for different modes
    subparsers = parser.add_subparsers(dest='mode', help='Operation mode')
    
    # SSH command mode (default)
    ssh_parser = subparsers.add_parser('ssh', help='Execute SSH commands (default mode)')
    ssh_parser.add_argument('-c', '--command', help='Command to execute')
    
    # LVM bootstrap mode
    lvm_parser = subparsers.add_parser('bootstrap-lvm', help='Bootstrap LVM on remote disk')
    lvm_parser.add_argument('--device', required=True, 
                           help='Device to bootstrap (e.g., /dev/sdc)')
    lvm_parser.add_argument('--mount-point', default='/mnt/github-backup',
                           help='Mount point for the logical volume (default: /mnt/github-backup)')
    lvm_parser.add_argument('--vg-name', default='github_vg',
                           help='Volume group name (default: github_vg)')
    lvm_parser.add_argument('--lv-name', default='github_lv',
                           help='Logical volume name (default: github_lv)')
    lvm_parser.add_argument('--check-only', action='store_true',
                           help='Only check disk status without making changes')
    lvm_parser.add_argument('-y', '--yes', action='store_true',
                           help='Skip confirmation prompt')
    
    # GitHub Backup Utils deployment
    deploy_parser = subparsers.add_parser('deploy-backup', help='Deploy GitHub Backup Utils')
    deploy_parser.add_argument('--github-host', required=True,
                             help='GitHub hostname (e.g., github.com or github.company.com)')
    deploy_parser.add_argument('--github-token', 
                             help='GitHub API token (required for github.com)')
    deploy_parser.add_argument('--version', default='latest',
                             help='Version to install (default: latest)')
    deploy_parser.add_argument('--backup-user', default='git-backup',
                             help='System user for backups (default: git-backup)')
    deploy_parser.add_argument('--backup-home', default='/home/git-backup',
                             help='Home directory for backup user (default: /home/git-backup)')
    deploy_parser.add_argument('--data-dir', default='/mnt/github-backup',
                             help='Data directory for backups (default: /mnt/github-backup)')
    deploy_parser.add_argument('--upgrade', action='store_true',
                             help='Upgrade existing installation')
    deploy_parser.add_argument('--force', action='store_true',
                             help='Force deployment even if already installed')
    deploy_parser.add_argument('--test-connection', action='store_true',
                             help='Test connection after deployment')
    deploy_parser.add_argument('-y', '--yes', action='store_true',
                             help='Skip confirmation prompt')
    
    # Test backup connection
    test_parser = subparsers.add_parser('test-backup', help='Test GitHub backup connection')
    test_parser.add_argument('--github-host',
                           help='Update GitHub hostname in config')
    test_parser.add_argument('--run-backup', action='store_true',
                           help='Run a test backup after connection test')
    
    args = parser.parse_args()
    
    # Default to SSH mode if no subcommand specified
    if args.mode is None:
        args.mode = 'ssh'
        args.command = None
    
    # Route to appropriate function
    if args.mode == 'bootstrap-lvm':
        return run_lvm_bootstrap(args)
    elif args.mode == 'deploy-backup':
        return run_github_backup_deploy(args)
    elif args.mode == 'test-backup':
        return run_test_backup(args)
    else:
        return run_ssh_commands(args)

if __name__ == "__main__":
    sys.exit(main())
