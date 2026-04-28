## Key takeaways
 
- **ASE v3 is per-ASE for DNS.** Treat each ASE as its own DNS namespace. Standing up a new ASE is a three-team event: Cloud (zone + vnet links), NetOps (ZPA segment + connector mapping), SysOps (conditional forwarder on DCs). Build a checklist.
- **`168.63.129.16` is Azure-only.** Anything on-prem that needs to resolve a Private DNS Zone needs a forwarder hop through an Azure-resident DNS server.
- **Wildcard ZPA segments scale better than per-app segments.** `*.scm.<ase>.appserviceenvironment.us` covers every Function App in that ASE forever; per-app entries become a backlog.
- **The "DNS works inside Azure but not on-prem" symptom is a forwarder problem 95% of the time.** The Azure VM curl test isolates the issue cleanly: if it works from inside the vnet but not from on-prem, you're done with Azure and DNS Zones — go talk to SysOps.
- **Order of testing matters.** Test from Azure first (validates the zone), then from on-prem (validates the forwarder chain), then the browser (validates ZPA). Each step rules out a layer.
