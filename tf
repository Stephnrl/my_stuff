terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aap = {
      source  = "ansible/aap"
      version = ">= 1.3.0"
    }
  }
}
