resource "azurerm_key_vault_certificate" "code_signing_cert" {
  name         = "code-signing-cert"
  key_vault_id = azurerm_key_vault.code_signing.id

  certificate_policy {
    issuer_parameters {
      name = "Unknown" # Allows you to download the CSR for DigiCert
    }

    key_properties {
      exportable = false
      key_type   = "RSA-HSM" # Matches Key Vault Premium HSM
      key_size   = 4096
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pem-file"
    }

    x509_certificate_properties {
      # Ensure this matches your DigiCert order exactly
      subject            = "CN=Your Company Name, O=Your Company, L=City, ST=State, C=US"
      validity_in_months = 12

      key_usage = [
        "digitalSignature",
        "contentCommitment" # Also known as Non-repudiation
      ]

      extended_key_usage = ["1.3.6.1.5.5.7.3.3"] # Code Signing OID
    }
  }
}
