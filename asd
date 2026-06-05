. Known-ish bug: tooling ignores AzureUSGovernment and calls public ARM

There is a GitHub issue in Azure/azure-workload-identity where azwi in AzureUSGovernment was reported to hit the public Azure endpoint instead of the Gov endpoint, even when --azure-env was set. The issue specifically says the endpoint used to look up the subscription was the public endpoint, not AzureUSGovernment, resulting in a 404.

That matches the general symptom you’re seeing:

management.azure.com

instead of:

management.usgovcloudapi.net

Microsoft’s Azure Gov endpoint table confirms that public Azure Resource Manager is management.azure.com, while Azure Government ARM is management.usgovcloudapi.net.

So yes, there has been a real known issue where Workload Identity tooling did not honor the Gov cloud environment correctly.

2. Blob CSI + Workload Identity may not work the way you expect

The Blob CSI Workload Identity deployment docs show two supported identity paths for the manual driver install:

Azure AD Application
User-assigned Managed Identity

The docs show setting Helm values like:

--set workloadIdentity.clientID=$CLIENT_ID
--set workloadIdentity.tenantID=$TENANT_ID

for either an Entra application or a user-assigned managed identity.

That means the clientID being passed is expected to be an Azure identity client ID, not a Kubernetes-native identity. The Kubernetes service account is only the federated subject:

system:serviceaccount:<namespace>:<service-account-name>

The service account itself does not own Azure permissions. It is used to exchange a projected Kubernetes token for an Azure token against an Entra application or UMI federated credential. The Blob CSI docs show this federated subject pattern when creating the federated credential.

So if by “Kubernetes identity” you mean the clientID is not an Entra app registration or UMI client ID, that is probably misconfigured.

The key point

For Workload Identity, this is the expected chain:

Kubernetes ServiceAccount
  -> projected service account token
  -> federated credential in Entra ID
  -> Azure AD Application or UMI client ID
  -> Azure token
  -> Azure ARM / Storage APIs

The Kubernetes service account is not the Azure identity. It only participates in the token exchange.

What I would inspect

Check your PV/StorageClass and CSI driver values for clientID:

kubectl get pv <pv-name> -o yaml | grep -i -A5 -B5 "clientID\|clientId\|workload\|secret\|identity"
kubectl get sc <storageclass-name> -o yaml | grep -i -A5 -B5 "clientID\|clientId\|workload\|secret\|identity"

Check Blob CSI Helm values if it was manually installed:

helm get values blob-csi-driver -n kube-system

or wherever it was installed:

helm list -A | grep -i blob

Then verify the client ID is a real Azure identity:

az identity show \
  --ids <identity-resource-id>

or for an app registration/service principal:

az ad sp show --id <client-id>

For Gov, also confirm your CLI is in the right cloud before checking:

az cloud show --query name -o tsv

Expected:

AzureUSGovernment
Also check Workload Identity injection issues

Azure Workload Identity has known issues around projected token access and injection. Its known issues page includes problems such as permission denied reading the projected service account token file and environment variables not being injected into pods in kube-system.

That matters because CSI drivers often run in kube-system. If the Blob CSI pod expects Workload Identity env vars/token projection but does not get them, it may fall back to another auth path or default cloud environment.

Check the Blob CSI pods:

kubectl get pod -n kube-system -l app=csi-blob-controller -o yaml | grep -i -A8 -B8 "AZURE\|CLIENT\|TENANT\|TOKEN\|workload"

And:

kubectl get pod -n kube-system -l app=csi-blob-node -o yaml | grep -i -A8 -B8 "AZURE\|CLIENT\|TENANT\|TOKEN\|workload"

You want to see whether these exist:

AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_FEDERATED_TOKEN_FILE
AZURE_AUTHORITY_HOST

For Gov, AZURE_AUTHORITY_HOST should point to the Gov login authority, not public Azure.

My read of your situation

Given your symptoms, I would suspect one of these:

Blob CSI Workload Identity config has a clientID, but it is not a real Azure UMI/app client ID.
The CSI driver is manually installed and Helm values defaulted to public Azure.
The Workload Identity webhook is not injecting Gov-specific env vars/token path into the CSI pods.
The CSI driver or azwi path has/had a bug where AzureUSGovernment is ignored and public ARM is used.
The driver falls back to /etc/kubernetes/azure.json, and that file says public Azure or lacks Gov cloud info.

The strongest proof would be this:

kubectl logs -n kube-system ds/csi-blob-node --all-containers=true --since=2h \
  | grep -Ei "management.azure.com|management.usgovcloudapi.net|AZURE_AUTHORITY_HOST|clientID|token|workload|cloud"

If the same log line shows clientID + management.azure.com, then yes, you have a strong case that the workload identity path or driver cloud config is not honoring Azure Gov.
