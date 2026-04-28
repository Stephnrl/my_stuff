## TL;DR
 
Microsoft migrated our App Service Environments from v2 to v3, which changed the DNS endpoint pattern for internal apps. Because our ILB ASE has no public exposure, the new endpoint suffix (`*.appserviceenvironment.us`) needs to resolve through private DNS — but no Private DNS Zone existed for it, no Zscaler ZPA rule covered it, and no on-prem conditional forwarder pointed at it. Kudu (and any direct SCM access) broke for every Function App in the affected ASEs.
 
Fix required changes in three places:
 
1. **Azure** — create a Private DNS Zone per ASE v3 and link it to the spoke vnets.
2. **Zscaler ZPA** — add the new domains and the ILB IP to the Azure App Connector application segments, including a wildcard for SCM/Kudu hostnames.
3. **On-prem DNS** — confirm conditional forwarders on the domain controllers point to the Azure-resident DNS resolver VMs, which in turn forward to Azure-provided DNS (168.63.129.16) and resolve the Private DNS Zones.
