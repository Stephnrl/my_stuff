# AWS Security Account Architecture — Technical Review

**Status:** Current
**Owner:** [Your Name / Team]
**Last Updated:** April 2026
**Environment:** AWS GovCloud (us-gov-west-1)

---

## Overview

This document describes the architecture of our centralized security account within our AWS Organization. The security account serves as the delegated administrator for AWS Config, GuardDuty, and Security Hub, providing org-wide visibility into compliance posture, threat detection, and security findings. All infrastructure is managed via Terraform and deployed through a GitHub Actions CI/CD pipeline using OIDC federation — no long-lived credentials are stored.

---

## AWS Organization Structure

Our AWS Organization consists of a management account, a dedicated security account, and multiple member (workload) accounts organized under OUs.

The **management account** is responsible for registering the security account as a delegated administrator for the following service principals:

- `config.amazonaws.com`
- `config-multiaccountsetup.amazonaws.com`
- `guardduty.amazonaws.com`
- `securityhub.amazonaws.com`

Trusted access is enabled at the Organization level for each of these service principals. This is a prerequisite for delegated admin functionality — delegation registration alone is not sufficient without trusted access enabled.

**Member accounts** are workload accounts where application infrastructure runs. These accounts have AWS Config recording enabled, and their configuration and compliance data flows into the security account via Config aggregation. GuardDuty and Security Hub findings from member accounts are also centrally aggregated.

---

## Security Account — Delegated Admin Services

### AWS Config

The security account is the delegated administrator for AWS Config. It operates two primary Config components:

**Configuration Aggregator** — An org-wide aggregator that collects configuration and compliance data from all member accounts and all regions. The aggregator uses a dedicated IAM role (`AWSConfigRoleForOrganizations` managed policy) with a trust policy allowing `config.amazonaws.com` to assume it. This provides a centralized compliance dashboard for reviewing resource configurations across the organization.

**Conformance Packs** — Organization-level conformance packs are deployed from the security account to all member accounts. Currently deployed packs include the Operational Best Practices for FedRAMP High (Part 1 and Part 2), aligned to CMMC Level 2 controls. These conformance packs evaluate resources against security controls and report compliance scores.

### Amazon GuardDuty

The security account is the delegated administrator for GuardDuty. It receives threat detection findings from all member accounts, including findings related to compromised credentials, unusual API activity, cryptocurrency mining, and malicious network behavior. GuardDuty findings are also forwarded to Security Hub for centralized triage.

### AWS Security Hub

The security account is the delegated administrator for Security Hub. Security Hub acts as the single pane of glass for all security findings across the organization. It receives findings from:

- AWS Config rule evaluations and conformance pack results
- GuardDuty threat detection findings
- IAM Access Analyzer external access findings
- Any additional integrated security services

Security Hub provides a consolidated compliance dashboard, supports automated remediation workflows, and can export findings for authorization and continuous monitoring reporting.

---

## Supporting Services

The following services run within the security account to support the overall security posture but are **not** delegated admin services:

**AWS CloudTrail** — Captures API audit logs for activity within the security account. Organization-level trails may be configured from the management account separately.

**Amazon CloudWatch** — Provides metrics, alarms, and log aggregation for monitoring the health and performance of security tooling within the account.

**IAM Access Analyzer** — Identifies resources that are shared with external entities (cross-account access, public access). Findings are forwarded to Security Hub.

---

## IAM Roles

There are two distinct IAM roles involved in this architecture. It is important to understand the separation of concerns between them.

### Terraform Execution Role

**Purpose:** This is the role assumed by the CI/CD pipeline to deploy and manage infrastructure.

**Trust Policy:** Federated trust via GitHub OIDC provider. Only the designated GitHub repository and branch can assume this role. No long-lived access keys exist.

**Permissions (key policies):**

- `organizations:ListDelegatedAdministrators` — Required by the Config API when calling `PutConfigurationAggregator`. Without this, the aggregator creation fails with `OrganizationAccessDeniedException`.
- `organizations:DescribeOrganization`
- `organizations:ListAccounts`
- `organizations:ListAWSServiceAccessForOrganization`
- `config:*` — Full Config permissions for managing aggregators, conformance packs, and rules.
- Additional permissions as needed for GuardDuty, Security Hub, and supporting service configuration.

### Config Aggregator Role

**Purpose:** This is the role that AWS Config assumes at runtime to collect configuration and compliance data from member accounts.

**Trust Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "config.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Permissions:** AWS managed policy `AWSConfigRoleForOrganizations`, which grants read-only access to Organizations APIs needed for data collection.

---

## CI/CD Pipeline

All infrastructure is managed as code in a GitHub repository and deployed via Terraform.

**Deployment flow:**

1. Engineer pushes code to the GitHub repository.
2. GitHub Actions workflow triggers on merge to the main branch.
3. The workflow authenticates to AWS using OIDC federation — GitHub's OIDC provider issues a short-lived token, which is exchanged for temporary AWS credentials by assuming the Terraform execution role.
4. Terraform runs `plan` and `apply` against the security account in `us-gov-west-1`.
5. Terraform manages the Config aggregator, conformance packs, GuardDuty configuration, Security Hub settings, IAM roles, and all supporting resources.

**No long-lived credentials are used.** The OIDC trust relationship ensures that only the authorized repository and branch can assume the deployment role, and credentials expire after the workflow completes.

---

## Service Control Policy (SCP) Considerations

The organization applies a restrictive SCP (`deny-org-nonadmin`) to member account OUs that denies all `organizations:*` API calls. Because the security account resides under an OU targeted by this SCP, an explicit exception is required.

**SCP exception:**
```json
{
  "Effect": "Deny",
  "Action": "organizations:*",
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:PrincipalAccount": "<security-account-id>"
    }
  }
}
```

This exception allows the security account to make the `organizations:ListDelegatedAdministrators` and other Organizations API calls required by AWS Config and other delegated admin services. Without this exception, Config aggregator creation and conformance pack deployment will fail with `OrganizationAccessDeniedException`.

**Important:** This exception must be documented and maintained. If the SCP is modified or the security account is moved to a different OU, the exception must follow. Any team modifying SCPs should be aware of this dependency.

---

## Prerequisites and Dependencies

For this architecture to function correctly, the following must be in place:

1. **Trusted access enabled** at the Organization level for `config.amazonaws.com`, `guardduty.amazonaws.com`, and `securityhub.amazonaws.com`. This is separate from delegated admin registration — both are required.
2. **Delegated admin registered** for each service principal from the management account.
3. **SCP exception** in place for the security account to allow `organizations:*` calls.
4. **OIDC identity provider** configured in the security account's IAM for the GitHub Actions provider (`token.actions.githubusercontent.com`).
5. **Config recording enabled** in all member accounts for conformance pack evaluations to produce results.

---

## Troubleshooting

**`OrganizationAccessDeniedException` when creating Config aggregator:**

- Verify the Terraform execution role has `organizations:ListDelegatedAdministrators` permission.
- Confirm the SCP exception is in place for the security account.
- Confirm trusted access is enabled for `config.amazonaws.com` (not just `config-multiaccountsetup.amazonaws.com`).
- Confirm the delegated admin registration is active for `config.amazonaws.com`.
- Run `aws sts get-caller-identity` to verify the correct role is being assumed.

**Config aggregator role assumption failures:**

- Verify the aggregator role's trust policy includes `config.amazonaws.com` as a trusted principal.
- Ensure the role ARN uses the correct GovCloud partition: `arn:aws-us-gov:iam::...` not `arn:aws:iam::...`.

---

## References

- [AWS Config Delegated Administrator](https://docs.aws.amazon.com/config/latest/developerguide/aggregated-register-delegated-administrator.html)
- [Operational Best Practices for FedRAMP High in GovCloud](https://aws.amazon.com/blogs/mt/operational-best-practices-for-fedramp-compliance-in-aws-govcloud-with-aws-config/)
- [Using Delegated Admin for AWS Config Operations](https://aws.amazon.com/blogs/mt/using-delegated-admin-for-aws-config-operations-and-aggregation/)
- [GitHub OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
