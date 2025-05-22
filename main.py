#!/usr/bin/env python3
import sys
from src.ssh_client.connection_manager import ssh_connection
from src.utils.logger import setup_logger

def main():
    logger = setup_logger('main')
    
    try:
        # Using context manager for automatic connection handling
        with ssh_connection(use_key=True) as ssh:
            # Execute commands
            output, error, exit_code = ssh.execute_command('ls -la')
            
            if exit_code == 0:
                print("Command output:")
                print(output)
            else:
                print("Command failed:")
                print(error)
            
            # Execute another command
            output, error, exit_code = ssh.execute_command('df -h')
            print("\nDisk usage:")
            print(output)
            
    except Exception as e:
        logger.error(f"Error in main: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
