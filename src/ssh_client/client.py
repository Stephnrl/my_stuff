import paramiko
import getpass
from typing import Optional, Tuple
from src.utils.logger import setup_logger
from src.config.settings import SSHConfig

class SecureSSHClient:
    def __init__(self):
        self.logger = setup_logger(__name__, SSHConfig.LOG_LEVEL)
        self.client = None
        self.config = SSHConfig()
        
    def connect(self, password: Optional[str] = None, use_key: bool = True) -> bool:
        """
        Establish SSH connection with security best practices
        """
        try:
            self.client = paramiko.SSHClient()
            
            # Load known hosts for host key verification
            try:
                self.client.load_system_host_keys()
                self.client.load_host_keys(os.path.expanduser('~/.ssh/known_hosts'))
            except FileNotFoundError:
                self.logger.warning("Known hosts file not found")
            
            # Set policy for unknown hosts (use with caution in production)
            # For production, use paramiko.RejectPolicy() instead
            self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            # Connection parameters
            connect_kwargs = {
                'hostname': self.config.HOST,
                'port': self.config.PORT,
                'username': self.config.USERNAME,
                'timeout': self.config.TIMEOUT,
                'auth_timeout': self.config.AUTH_TIMEOUT,
                'banner_timeout': self.config.BANNER_TIMEOUT,
                'disabled_algorithms': {'pubkeys': ['rsa-sha2-256', 'rsa-sha2-512']} if not use_key else None
            }
            
            if use_key and self.config.KEY_PATH:
                # Use key-based authentication
                private_key = paramiko.RSAKey.from_private_key_file(
                    self.config.KEY_PATH,
                    password=getpass.getpass("Enter SSH key passphrase: ") if password is None else password
                )
                connect_kwargs['pkey'] = private_key
            else:
                # Use password authentication
                if password is None:
                    password = getpass.getpass(f"Enter password for {self.config.USERNAME}@{self.config.HOST}: ")
                connect_kwargs['password'] = password
            
            self.client.connect(**connect_kwargs)
            self.logger.info(f"Successfully connected to {self.config.HOST}")
            return True
            
        except paramiko.AuthenticationException:
            self.logger.error("Authentication failed")
            return False
        except paramiko.SSHException as e:
            self.logger.error(f"SSH connection error: {e}")
            return False
        except Exception as e:
            self.logger.error(f"Unexpected error: {e}")
            return False
    
    def execute_command(self, command: str) -> Tuple[str, str, int]:
        """
        Execute command on remote server
        """
        if not self.client:
            raise RuntimeError("Not connected to SSH server")
        
        try:
            stdin, stdout, stderr = self.client.exec_command(command)
            
            # Read output
            output = stdout.read().decode('utf-8')
            error = stderr.read().decode('utf-8')
            exit_status = stdout.channel.recv_exit_status()
            
            self.logger.info(f"Executed command: {command}")
            
            return output, error, exit_status
            
        except Exception as e:
            self.logger.error(f"Command execution failed: {e}")
            raise
    
    def close(self):
        """Close SSH connection"""
        if self.client:
            self.client.close()
            self.logger.info("SSH connection closed")
