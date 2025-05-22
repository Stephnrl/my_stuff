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

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='SSH Client with LVM Bootstrap capability')
    
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
    
    args = parser.parse_args()
    
    # Default to SSH mode if no subcommand specified
    if args.mode is None:
        args.mode = 'ssh'
        args.command = None
    
    # Route to appropriate function
    if args.mode == 'bootstrap-lvm':
        return run_lvm_bootstrap(args)
    else:
        return run_ssh_commands(args)

if __name__ == "__main__":
    sys.exit(main())
