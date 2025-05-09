# locals.tf

locals {
  # Used for role assignments
  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions/"
  
  # Default tags
  default_tags = {
    module       = "azure-shared-image-gallery"
    environment  = var.environment
    created_by   = "terraform"
    created_date = formatdate("YYYY-MM-DD", timestamp())
  }
}

# Add a variable for environment to be used in default tags
variable "environment" {
  description = "Environment name to be used in default tags."
  type        = string
  default     = "dev"
}
