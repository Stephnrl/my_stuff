import os
from dotenv import load_dotenv

load_dotenv()

class SSHConfig:
    HOST = os.getenv('SSH_HOST')
    PORT = int(os.getenv('SSH_PORT', 22))
    USERNAME = os.getenv('SSH_USERNAME')
    KEY_PATH = os.getenv('SSH_KEY_PATH')
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    
    # Security settings
    TIMEOUT = 30
    AUTH_TIMEOUT = 30
    BANNER_TIMEOUT = 30
    
    # Allowed host keys algorithms (more secure ones)
    HOST_KEY_ALGORITHMS = [
        'ssh-ed25519',
        'ecdsa-sha2-nistp256',
        'ecdsa-sha2-nistp384',
        'ecdsa-sha2-nistp521',
        'rsa-sha2-512',
        'rsa-sha2-256',
    ]
