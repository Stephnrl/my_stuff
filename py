# lookup_plugins/azure_keyvault.py

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

DOCUMENTATION = """
    name: azure_keyvault
    author: Your Name
    version_added: "1.0"
    short_description: Lookup secrets from Azure Key Vault
    description:
        - This lookup returns secret values from Azure Key Vault
        - Uses managed identity for authentication
    options:
      _terms:
        description: Secret name(s) to retrieve
        required: True
      vault_name:
        description: Name of the Azure Key Vault
        required: True
        type: string
    notes:
      - Requires azure-keyvault-secrets, azure-identity, azure-core packages
    examples:
      - name: Get a secret
        debug:
          msg: "{{ lookup('azure_keyvault', 'my-secret', vault_name='my-vault') }}"
      
      - name: Get multiple secrets
        debug:
          msg: "{{ lookup('azure_keyvault', 'secret1', 'secret2', vault_name='my-vault') }}"
"""

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase

try:
    from azure.identity import DefaultAzureCredential
    from azure.keyvault.secrets import SecretClient
    from azure.core.exceptions import ResourceNotFoundError
    HAS_AZURE = True
except ImportError:
    HAS_AZURE = False


class LookupModule(LookupBase):
    
    def run(self, terms, variables=None, **kwargs):
        if not HAS_AZURE:
            raise AnsibleError(
                "azure-keyvault-secrets, azure-identity, and azure-core "
                "python packages are required for the azure_keyvault lookup plugin"
            )
        
        # Get vault_name from kwargs
        vault_name = kwargs.get('vault_name', None)
        if not vault_name:
            raise AnsibleError("vault_name is required for azure_keyvault lookup")
        
        # Build vault URL
        vault_url = f"https://{vault_name}.vault.azure.net"
        
        # Initialize Azure client
        try:
            credential = DefaultAzureCredential()
            client = SecretClient(vault_url=vault_url, credential=credential)
        except Exception as e:
            raise AnsibleError(f"Failed to initialize Azure Key Vault client: {str(e)}")
        
        # Fetch secrets
        ret = []
        for term in terms:
            try:
                secret = client.get_secret(term)
                ret.append(secret.value)
            except ResourceNotFoundError:
                raise AnsibleError(f"Secret '{term}' not found in Key Vault '{vault_name}'")
            except Exception as e:
                raise AnsibleError(f"Failed to retrieve secret '{term}': {str(e)}")
        
        return ret
