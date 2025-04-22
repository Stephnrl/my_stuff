#!/usr/bin/env python3
"""
Docker Container Wrapper - Run containers like binaries without third-party dependencies.
Supports different images (Ansible, Golang, etc.) dynamically.
"""

import os
import sys
import subprocess
import argparse
import json
import platform


class DockerWrapper:
    def __init__(self):
        # Configuration - can be customized
        self.config_file = os.path.expanduser("~/.docker_wrapper.json")
        self.default_config = {
            "images": {
                "ansible": {
                    "tag": "ansible-azure",
                    "dockerfile": "Dockerfile.ansible",
                    "entrypoint": "ansible-playbook",
                    "mount_paths": [
                        {"host": ".", "container": "/ansible/playbooks"},
                        {"host": "~/.azure", "container": "/root/.azure"}
                    ]
                },
                "golang": {
                    "tag": "golang-dev",
                    "dockerfile": "Dockerfile.golang",
                    "entrypoint": "/bin/bash",
                    "mount_paths": [
                        {"host": ".", "container": "/go/src/app"}
                    ]
                }
            },
            "default_image": "ansible"
        }
        
        # Load or create config
        self.config = self.load_config()
        
    def load_config(self):
        """Load configuration or create default if not exists"""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r') as f:
                    return json.load(f)
            except json.JSONDecodeError:
                print(f"Error reading config file. Using default config.")
                return self.default_config
        else:
            # Create default config
            try:
                os.makedirs(os.path.dirname(self.config_file), exist_ok=True)
                with open(self.config_file, 'w') as f:
                    json.dump(self.default_config, f, indent=2)
                print(f"Created default config at {self.config_file}")
            except Exception as e:
                print(f"Warning: Failed to create config file: {e}")
            return self.default_config
            
    def save_config(self):
        """Save configuration to file"""
        try:
            with open(self.config_file, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            print(f"Warning: Failed to save config: {e}")
            
    def fix_path(self, path):
        """Fix path for current OS and expand user directory"""
        if path.startswith('~'):
            path = os.path.expanduser(path)
        
        # Convert relative paths to absolute
        if not os.path.isabs(path):
            path = os.path.abspath(path)
            
        # For Windows, convert to Docker-compatible path
        if platform.system() == 'Windows':
            # Convert path separators and drive letter format
            path = path.replace('\\', '/')
            if ':' in path:  # Handle drive letter
                path = '/' + path[0].lower() + path[2:]
        
        return path
            
    def build_image(self, image_name):
        """Build Docker image"""
        if image_name not in self.config['images']:
            print(f"Error: Image '{image_name}' not found in configuration.")
            return False
            
        image_config = self.config['images'][image_name]
        tag = image_config['tag']
        dockerfile = image_config['dockerfile']
        
        if not os.path.exists(dockerfile):
            print(f"Error: Dockerfile '{dockerfile}' not found.")
            return False
            
        print(f"Building Docker image: {tag}")
        result = subprocess.run(['docker', 'build', '-t', tag, '-f', dockerfile, '.'], 
                               capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"Error building image: {result.stderr}")
            return False
            
        print(f"Successfully built image: {tag}")
        return True
        
    def run_container(self, image_name, cmd_args=None):
        """Run Docker container with the specified image"""
        if image_name not in self.config['images']:
            print(f"Error: Image '{image_name}' not found in configuration.")
            return False
            
        image_config = self.config['images'][image_name]
        tag = image_config['tag']
        entrypoint = image_config.get('entrypoint', '/bin/bash')
        mount_paths = image_config.get('mount_paths', [])
        
        # Build docker run command
        cmd = ['docker', 'run', '-it', '--rm']
        
        # Add volume mounts
        for mount in mount_paths:
            host_path = self.fix_path(mount['host'])
            container_path = mount['container']
            cmd.extend(['-v', f"{host_path}:{container_path}"])
            
        # Add entrypoint
        cmd.extend(['--entrypoint', entrypoint])
        
        # Add image name
        cmd.append(tag)
        
        # Add command arguments
        if cmd_args:
            cmd.extend(cmd_args)
            
        # Run the container
        print(f"Running container: {' '.join(cmd)}")
        return subprocess.run(cmd)
        
    def list_images(self):
        """List available images in configuration"""
        print("Available images:")
        for name, config in self.config['images'].items():
            print(f"  {name} ({config['tag']})")
            
    def add_image(self, name, tag, dockerfile, entrypoint=None):
        """Add a new image to configuration"""
        if name in self.config['images']:
            print(f"Warning: Image '{name}' already exists. Updating configuration.")
            
        self.config['images'][name] = {
            'tag': tag,
            'dockerfile': dockerfile,
            'entrypoint': entrypoint or '/bin/bash',
            'mount_paths': [{'host': '.', 'container': '/workspace'}]
        }
        
        self.save_config()
        print(f"Added image '{name}' to configuration.")
        
    def remove_image(self, name):
        """Remove an image from configuration"""
        if name not in self.config['images']:
            print(f"Error: Image '{name}' not found in configuration.")
            return False
            
        del self.config['images'][name]
        self.save_config()
        print(f"Removed image '{name}' from configuration.")
        return True
        
    def clean_image(self, image_name):
        """Remove Docker image"""
        if image_name not in self.config['images']:
            print(f"Error: Image '{image_name}' not found in configuration.")
            return False
            
        tag = self.config['images'][image_name]['tag']
        print(f"Removing Docker image: {tag}")
        
        result = subprocess.run(['docker', 'rmi', tag], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error removing image: {result.stderr}")
            return False
            
        print(f"Successfully removed image: {tag}")
        return True
        
    def set_default_image(self, image_name):
        """Set default image"""
        if image_name not in self.config['images']:
            print(f"Error: Image '{image_name}' not found in configuration.")
            return False
            
        self.config['default_image'] = image_name
        self.save_config()
        print(f"Set default image to '{image_name}'.")
        return True


def main():
    # Create main parser
    parser = argparse.ArgumentParser(description='Docker Container Wrapper')
    subparsers = parser.add_subparsers(dest='command', help='Command to run')
    
    # Build command
    build_parser = subparsers.add_parser('build', help='Build Docker image')
    build_parser.add_argument('image', nargs='?', help='Image to build')
    
    # Run command
    run_parser = subparsers.add_parser('run', help='Run Docker container')
    run_parser.add_argument('image', nargs='?', help='Image to run')
    run_parser.add_argument('args', nargs='*', help='Arguments to pass to container')
    
    # Shell command
    shell_parser = subparsers.add_parser('shell', help='Open shell in container')
    shell_parser.add_argument('image', nargs='?', help='Image to open shell with')
    
    # List command
    subparsers.add_parser('list', help='List available images')
    
    # Add command
    add_parser = subparsers.add_parser('add', help='Add new image to configuration')
    add_parser.add_argument('name', help='Name for the image configuration')
    add_parser.add_argument('tag', help='Docker image tag')
    add_parser.add_argument('dockerfile', help='Path to Dockerfile')
    add_parser.add_argument('--entrypoint', help='Container entrypoint')
    
    # Remove command
    remove_parser = subparsers.add_parser('remove', help='Remove image from configuration')
    remove_parser.add_argument('image', help='Image to remove')
    
    # Clean command
    clean_parser = subparsers.add_parser('clean', help='Remove Docker image')
    clean_parser.add_argument('image', nargs='?', help='Image to remove')
    
    # Set default command
    default_parser = subparsers.add_parser('default', help='Set default image')
    default_parser.add_argument('image', help='Image to set as default')
    
    # Parse arguments
    args = parser.parse_args()
    
    # Create wrapper instance
    wrapper = DockerWrapper()
    
    # If no arguments, show help
    if not args.command:
        parser.print_help()
        return 1
        
    # Handle commands
    if args.command == 'build':
        image = args.image or wrapper.config['default_image']
        return 0 if wrapper.build_image(image) else 1
        
    elif args.command == 'run':
        image = args.image or wrapper.config['default_image']
        result = wrapper.run_container(image, args.args)
        return result.returncode
        
    elif args.command == 'shell':
        image = args.image or wrapper.config['default_image']
        result = wrapper.run_container(image)
        return result.returncode
        
    elif args.command == 'list':
        wrapper.list_images()
        return 0
        
    elif args.command == 'add':
        wrapper.add_image(args.name, args.tag, args.dockerfile, args.entrypoint)
        return 0
        
    elif args.command == 'remove':
        return 0 if wrapper.remove_image(args.image) else 1
        
    elif args.command == 'clean':
        image = args.image or wrapper.config['default_image']
        return 0 if wrapper.clean_image(image) else 1
        
    elif args.command == 'default':
        return 0 if wrapper.set_default_image(args.image) else 1


if __name__ == '__main__':
    sys.exit(main())
