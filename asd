Good clarification — that's a much simpler and more focused request. Here are the updated answers:

Scope and Level of Access Requested
Service account requiring SSH (Linux) and/or WinRM (Windows) access to managed virtual machines within our Azure Government Cloud environment. The account will need:

Local administrator or sudo/root privileges on target Linux hosts (SSH)
Local administrator privileges on target Windows hosts (WinRM)
No Azure control plane or data plane access required — Azure inventory and API interactions are handled separately via an existing Service Principal (SPN)


Detailed Business Justification
Our team is implementing Red Hat Ansible Automation Platform 2.5 to automate configuration management across virtual machines in our Azure Government Cloud environment. A dedicated service account with SSH and WinRM credentials is required to allow AAP to remotely connect to and configure target Linux and Windows hosts via Ansible playbooks.
A dedicated service account ensures automation workflows are not tied to individual user credentials, provides a consistent and auditable identity for all Ansible-driven configuration activity, and supports our initiative to enforce immutable, repeatable infrastructure configuration. Azure inventory collection and all control/data plane interactions are already handled through an existing SPN — this account is strictly for remote host access and management.
