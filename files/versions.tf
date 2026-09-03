terraform {
  # optional() with defaults requires 1.3, lifecycle preconditions require 1.2.
  required_version = ">= 1.3"

  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = ">= 1.14"
    }
  }
}
