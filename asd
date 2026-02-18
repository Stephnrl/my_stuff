Here are polished answers for both fields:

Scope and Level of Access Requested
Service account to be used exclusively by Red Hat Ansible Automation Platform (AAP) 2.5 for automated configuration management and infrastructure operations within our Azure Government Cloud tenant. The account requires elevated permissions including, but not limited to:

Virtual Machine Contributor or equivalent RBAC role to provision, configure, start/stop, and decommission virtual machines
Reader access at the subscription or resource group level for inventory and state management
Any additional permissions required to manage associated VM resources (disks, NICs, NSGs) as needed by Ansible playbook execution

Access should be scoped to the designated Azure Gov Cloud tenant/subscription(s) and follow the principle of least privilege within those boundaries.

Detailed Business Justification
Our team is transitioning to an immutable infrastructure and configuration management model using Red Hat Ansible Automation Platform 2.5. To support this initiative, a dedicated service account is required to allow AAP to authenticate and execute Ansible playbooks against our Azure Government Cloud environment in an automated, non-interactive manner.
Using a dedicated service account rather than individual user credentials ensures that automation pipelines remain functional independent of personnel changes, reduces the risk of credential sprawl, and provides a clear audit trail of all automated actions performed against the environment. This account will enable our team to enforce consistent, repeatable, and auditable VM configuration across the environment, reducing manual intervention, configuration drift, and human error — directly supporting our broader DevOps and security compliance objectives.
