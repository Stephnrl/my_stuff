##############################################################
# AAP → AWS GovCloud OIDC federation
#
# Registers the AAP controller as an OIDC identity provider in
# IAM, then creates per-job-template roles that trust it.
##############################################################

locals {
  aap_issuer_url = "https://${var.aap_controller_hostname}${var.aap_oidc_path}"
  # AWS IAM stores the issuer without the scheme
  aap_issuer_key = "${var.aap_controller_hostname}${var.aap_oidc_path}"
}

# Fetch the TLS cert chain of the AAP OIDC issuer so we can pin its
# root CA thumbprint in IAM. IAM uses this to validate the JWKS endpoint.
data "tls_certificate" "aap_oidc" {
  url = local.aap_issuer_url
}

resource "aws_iam_openid_connect_provider" "aap" {
  url             = local.aap_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.aap_oidc.certificates[0].sha1_fingerprint]

  tags = {
    Name = "aap-controller-oidc"
  }
}

# One IAM role per job template (or logical group of templates).
module "job_template_role" {
  source = "./modules/aap-role"

  for_each = var.job_template_roles

  role_name           = "aap-${var.environment}-${each.key}"
  oidc_provider_arn   = aws_iam_openid_connect_provider.aap.arn
  oidc_issuer_key     = local.aap_issuer_key
  sub_pattern         = each.value.sub_pattern
  secret_arns         = each.value.secret_arns
  max_session_hours   = each.value.max_session_hours
  additional_policies = each.value.additional_policies
}
