import logging
import os
from datetime import datetime

def setup_logger(name, log_level='INFO'):
    """Set up logger with file and console handlers"""
    logger = logging.getLogger(name)
    logger.setLevel(getattr(logging, log_level))
    
    # Create logs directory if it doesn't exist
    os.makedirs('logs', exist_ok=True)
    
    # File handler
    fh = logging.FileHandler(f'logs/ssh_client_{datetime.now().strftime("%Y%m%d")}.log')
    fh.setLevel(logging.DEBUG)
    
    # Console handler
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)
    
    # Formatter
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    fh.setFormatter(formatter)
    ch.setFormatter(formatter)
    
    logger.addHandler(fh)
    logger.addHandler(ch)
    
    return logger
