## Root cause
 
The ASE was internal-only — fronted by an Internal Load Balancer with a private IP, sitting in a spoke vnet, with no public DNS records. Three independent gaps stacked on top of the v2 → v3 migration:
 
1. **No Private DNS Zone** existed for `<ase>.appserviceenvironment.us`. With no private zone and no public record (because the ASE is ILB), the hostname had nothing authoritative to resolve against.
2. **Zscaler ZPA had no application segment** covering the new `appserviceenvironment.us` suffix. Even after we fixed DNS, ZPA wouldn't route that traffic through the Azure App Connector to the ILB.
3. **On-prem DNS had no path** to query Azure Private DNS. On-prem domain controllers can't talk directly to Azure-provided DNS at `168.63.129.16` — that address is only reachable from inside an Azure vnet — so a conditional forwarder is needed to hand the query to a DNS resolver VM that does live inside Azure.
Any one of those gaps would have broken Kudu on its own. After the v3 migration, all three needed fixing.
