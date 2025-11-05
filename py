#!/usr/bin/env python3
# /tmp/ansible/fetch_secrets.py

import sys
import json
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

def get_secret(vault_name, secret_name):
    vault_url = f"https://{vault_name}.vault.azure.net"
    credential = DefaultAzureCredential()
    client = SecretClient(vault_url=vault_url, credential=credential)
    
    secret = client.get_secret(secret_name)
    return secret.value

if __name__ == "__main__":
    vault_name = sys.argv[1]
    secret_name = sys.argv[2]
    
    value = get_secret(vault_name, secret_name)
    print(json.dumps({"value": value}))
