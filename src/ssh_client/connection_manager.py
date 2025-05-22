from contextlib import contextmanager
from src.ssh_client.client import SecureSSHClient

@contextmanager
def ssh_connection(password=None, use_key=True):
    """
    Context manager for SSH connections
    """
    client = SecureSSHClient()
    try:
        if client.connect(password=password, use_key=use_key):
            yield client
        else:
            raise ConnectionError("Failed to establish SSH connection")
    finally:
        client.close()
