"""
LVM Bootstrap module for setting up data disks
"""

import time
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
from src.utils.logger import setup_logger

class DiskStatus(Enum):
    AVAILABLE = "available"
    IN_USE = "in_use"
    FORMATTED = "formatted"
    UNKNOWN = "unknown"

@dataclass
class DiskInfo:
    device: str
    size: str
    mountpoint: Optional[str]
    fstype: Optional[str]
    partitions: List[str]

class LVMBootstrap:
    """Bootstrap LVM configuration on Linux hosts"""
    
    def __init__(self, ssh_client):
        self.ssh = ssh_client
        self.logger = setup_logger(__name__)
        
    def check_disk_availability(self, device: str) -> DiskStatus:
        """Check if disk is available for LVM setup"""
        self.logger.info(f"Checking disk availability for {device}")
        
        # Check if device exists
        output, _, exit_code = self.ssh.execute_command(f"test -e {device} && echo 'exists'")
        if exit_code != 0 or 'exists' not in output:
            self.logger.warning(f"Device {device} does not exist")
            return DiskStatus.UNKNOWN
        
        # Check if disk is already in use
        output, _, _ = self.ssh.execute_command(f"lsblk -no MOUNTPOINT {device} 2>/dev/null")
        if output.strip():
            self.logger.info(f"Device {device} is mounted at {output.strip()}")
            return DiskStatus.IN_USE
        
        # Check for existing partitions
        output, _, _ = self.ssh.execute_command(f"lsblk -no NAME,TYPE {device} 2>/dev/null | grep -c part || echo 0")
        if output.strip() and int(output.strip()) > 0:
            self.logger.info(f"Device {device} has existing partitions")
            return DiskStatus.FORMATTED
        
        # Check for existing filesystem
        output, _, exit_code = self.ssh.execute_command(f"sudo blkid {device} 2>/dev/null")
        if exit_code == 0 and output.strip():
            self.logger.info(f"Device {device} has existing filesystem")
            return DiskStatus.FORMATTED
        
        return DiskStatus.AVAILABLE
    
    def get_disk_info(self, device: str) -> DiskInfo:
        """Get detailed disk information"""
        # Get size
        size_output, _, _ = self.ssh.execute_command(f"lsblk -bno SIZE {device} 2>/dev/null")
        size_bytes = int(size_output.strip()) if size_output.strip() else 0
        size_gb = size_bytes / (1024**3)
        
        # Get mount and filesystem info
        mount_output, _, _ = self.ssh.execute_command(f"lsblk -no MOUNTPOINT {device} 2>/dev/null")
        fs_output, _, _ = self.ssh.execute_command(f"lsblk -no FSTYPE {device} 2>/dev/null")
        
        # Get partitions
        part_output, _, _ = self.ssh.execute_command(
            f"lsblk -lno NAME,TYPE {device} 2>/dev/null | grep part | awk '{{print \"/dev/\"$1}}'"
        )
        partitions = [p.strip() for p in part_output.split('\n') if p.strip()]
        
        return DiskInfo(
            device=device,
            size=f"{size_gb:.2f}GB",
            mountpoint=mount_output.strip() or None,
            fstype=fs_output.strip() or None,
            partitions=partitions
        )
    
    def wipe_disk(self, device: str) -> bool:
        """Safely wipe disk signatures"""
        self.logger.warning(f"Wiping disk signatures from {device}")
        
        try:
            # Unmount if mounted
            self.ssh.execute_command(f"sudo umount {device}* 2>/dev/null || true")
            
            # Remove LVM signatures if present
            self.ssh.execute_command(f"sudo pvremove -ff {device} 2>/dev/null || true")
            
            # Wipe filesystem signatures
            output, error, exit_code = self.ssh.execute_command(f"sudo wipefs -a {device}")
            if exit_code != 0:
                self.logger.error(f"Failed to wipe disk: {error}")
                return False
            
            # Clear partition table
            self.ssh.execute_command(f"sudo dd if=/dev/zero of={device} bs=1M count=10 status=none")
            
            time.sleep(2)  # Give system time to recognize changes
            return True
            
        except Exception as e:
            self.logger.error(f"Error wiping disk: {e}")
            return False
    
    def create_partition(self, device: str) -> Optional[str]:
        """Create a single partition using entire disk"""
        self.logger.info(f"Creating partition on {device}")
        
        try:
            # Create GPT partition table and single partition
            parted_commands = [
                f"sudo parted -s {device} mklabel gpt",
                f"sudo parted -s {device} mkpart primary 1MiB 100%",
                f"sudo parted -s {device} set 1 lvm on"
            ]
            
            for cmd in parted_commands:
                output, error, exit_code = self.ssh.execute_command(cmd)
                if exit_code != 0:
                    self.logger.error(f"Partition command failed: {error}")
                    return None
            
            # Let kernel recognize new partition
            self.ssh.execute_command(f"sudo partprobe {device}")
            time.sleep(2)
            
            # Determine partition device name
            partition = f"{device}1" if not device.endswith(('1', '2', '3', '4')) else f"{device}p1"
            
            # Verify partition exists
            output, _, exit_code = self.ssh.execute_command(f"test -e {partition} && echo 'exists'")
            if exit_code != 0 or 'exists' not in output:
                self.logger.error(f"Partition {partition} was not created")
                return None
            
            return partition
            
        except Exception as e:
            self.logger.error(f"Error creating partition: {e}")
            return None
    
    def setup_lvm(self, partition: str, vg_name: str, lv_name: str, lv_size: str = "100%VG") -> Optional[str]:
        """Setup LVM with physical volume, volume group, and logical volume"""
        self.logger.info(f"Setting up LVM on {partition}")
        
        try:
            # Create physical volume
            self.logger.info(f"Creating physical volume on {partition}")
            output, error, exit_code = self.ssh.execute_command(f"sudo pvcreate {partition}")
            if exit_code != 0:
                self.logger.error(f"Failed to create physical volume: {error}")
                return None
            
            # Create volume group
            self.logger.info(f"Creating volume group '{vg_name}'")
            output, error, exit_code = self.ssh.execute_command(f"sudo vgcreate {vg_name} {partition}")
            if exit_code != 0:
                self.logger.error(f"Failed to create volume group: {error}")
                return None
            
            # Create logical volume
            self.logger.info(f"Creating logical volume '{lv_name}' with size {lv_size}")
            if lv_size.endswith("%VG"):
                cmd = f"sudo lvcreate -l {lv_size} -n {lv_name} {vg_name}"
            else:
                cmd = f"sudo lvcreate -L {lv_size} -n {lv_name} {vg_name}"
            
            output, error, exit_code = self.ssh.execute_command(cmd)
            if exit_code != 0:
                self.logger.error(f"Failed to create logical volume: {error}")
                return None
            
            return f"/dev/{vg_name}/{lv_name}"
            
        except Exception as e:
            self.logger.error(f"Error setting up LVM: {e}")
            return None
    
    def format_filesystem(self, device: str, fstype: str = "ext4") -> bool:
        """Format device with specified filesystem"""
        self.logger.info(f"Formatting {device} with {fstype}")
        
        try:
            fs_options = {
                "ext4": "-t ext4 -E lazy_itable_init=0,lazy_journal_init=0",
                "xfs": "-t xfs",
                "btrfs": "-t btrfs"
            }
            
            options = fs_options.get(fstype, "-t ext4")
            output, error, exit_code = self.ssh.execute_command(f"sudo mkfs {options} {device}")
            
            if exit_code != 0:
                self.logger.error(f"Failed to format filesystem: {error}")
                return False
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error formatting filesystem: {e}")
            return False
    
    def mount_filesystem(self, device: str, mount_point: str) -> bool:
        """Mount filesystem and update fstab"""
        self.logger.info(f"Mounting {device} to {mount_point}")
        
        try:
            # Create mount point
            self.ssh.execute_command(f"sudo mkdir -p {mount_point}")
            
            # Mount filesystem
            output, error, exit_code = self.ssh.execute_command(f"sudo mount {device} {mount_point}")
            if exit_code != 0:
                self.logger.error(f"Failed to mount filesystem: {error}")
                return False
            
            # Get UUID
            uuid_output, _, _ = self.ssh.execute_command(f"sudo blkid -s UUID -o value {device}")
            uuid = uuid_output.strip()
            
            if uuid:
                # Add to fstab
                fstab_entry = f"UUID={uuid} {mount_point} ext4 defaults,nofail 0 2"
                self.ssh.execute_command(f"echo '{fstab_entry}' | sudo tee -a /etc/fstab")
            else:
                self.logger.warning("Could not get UUID, fstab not updated")
            
            # Set permissions for backup usage
            self.ssh.execute_command(f"sudo chmod 755 {mount_point}")
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error mounting filesystem: {e}")
            return False
    
    def verify_setup(self, vg_name: str, lv_name: str) -> Dict[str, any]:
        """Verify LVM setup completed successfully"""
        self.logger.info("Verifying LVM setup")
        
        verification = {
            "success": True,
            "vg_info": {},
            "lv_info": {},
            "mount_info": {}
        }
        
        try:
            # Check volume group
            output, _, exit_code = self.ssh.execute_command(f"sudo vgdisplay {vg_name} 2>/dev/null")
            verification["vg_info"]["exists"] = exit_code == 0
            
            # Check logical volume
            output, _, exit_code = self.ssh.execute_command(f"sudo lvdisplay /dev/{vg_name}/{lv_name} 2>/dev/null")
            verification["lv_info"]["exists"] = exit_code == 0
            
            # Check mount
            mount_output, _, _ = self.ssh.execute_command(f"mount | grep /dev/{vg_name}/{lv_name}")
            if mount_output.strip():
                mount_point = mount_output.split()[2]
                verification["mount_info"]["mounted"] = True
                verification["mount_info"]["mount_point"] = mount_point
                
                # Check available space
                df_output, _, _ = self.ssh.execute_command(f"df -h {mount_point} | tail -1")
                df_parts = df_output.split()
                if len(df_parts) >= 4:
                    verification["mount_info"]["size"] = df_parts[1]
                    verification["mount_info"]["available"] = df_parts[3]
            
        except Exception as e:
            verification["success"] = False
            verification["error"] = str(e)
        
        return verification
    
    def bootstrap_disk(self, device: str, mount_point: str = "/mnt/github-backup", 
                      vg_name: str = "github_vg", lv_name: str = "github_lv") -> bool:
        """Complete bootstrap process for disk"""
        self.logger.info(f"Starting bootstrap process for {device}")
        
        try:
            # Step 1: Check disk availability
            status = self.check_disk_availability(device)
            disk_info = self.get_disk_info(device)
            
            self.logger.info(f"Disk {device} status: {status.value}")
            self.logger.info(f"Disk size: {disk_info.size}")
            
            if status == DiskStatus.IN_USE:
                self.logger.error(f"Disk {device} is already in use")
                return False
            
            if status == DiskStatus.UNKNOWN:
                self.logger.error(f"Disk {device} not found")
                return False
            
            if status == DiskStatus.FORMATTED:
                self.logger.warning(f"Disk {device} has existing data - wiping")
                if not self.wipe_disk(device):
                    return False
            
            # Step 2: Create partition
            partition = self.create_partition(device)
            if not partition:
                return False
            self.logger.info(f"Created partition: {partition}")
            
            # Step 3: Setup LVM
            lv_device = self.setup_lvm(partition, vg_name, lv_name)
            if not lv_device:
                return False
            self.logger.info(f"Created logical volume: {lv_device}")
            
            # Step 4: Format filesystem
            if not self.format_filesystem(lv_device, "ext4"):
                return False
            
            # Step 5: Mount filesystem
            if not self.mount_filesystem(lv_device, mount_point):
                return False
            
            # Step 6: Create backup directory structure
            self.logger.info("Creating directory structure")
            backup_dirs = [
                f"{mount_point}/repositories",
                f"{mount_point}/metadata",
                f"{mount_point}/logs",
                f"{mount_point}/temp"
            ]
            
            for dir_path in backup_dirs:
                self.ssh.execute_command(f"sudo mkdir -p {dir_path}")
                self.ssh.execute_command(f"sudo chmod 755 {dir_path}")
            
            # Step 7: Verify setup
            verification = self.verify_setup(vg_name, lv_name)
            
            if verification["success"]:
                self.logger.info("Bootstrap completed successfully!")
                self.logger.info(f"Mount point: {mount_point}")
                self.logger.info(f"Available space: {verification['mount_info'].get('available', 'Unknown')}")
                return True
            else:
                self.logger.error("Verification failed")
                return False
            
        except Exception as e:
            self.logger.error(f"Bootstrap failed: {e}")
            return False
