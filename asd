## DNS resolution flow (after the fix)
 
When an on-prem user hits `<app>.scm.abccloud1.appserviceenvironment.us`:
 
1. Browser asks the workstation's configured DNS — an **on-prem domain controller**.
2. The DC has a **conditional forwarder** for `appserviceenvironment.us` pointing to a pair of **Azure-resident DNS resolver VMs**.
3. Those resolver VMs sit inside an Azure vnet, so they can query the **Azure-provided DNS at 168.63.129.16**.
4. 168.63.129.16 resolves the name through the **Private DNS Zone** for that ASE, which is linked to the vnet.
5. The zone returns the **ILB private IP**.
Confluence Mermaid (renders if your space has the Mermaid macro / extension; otherwise see the SVG attached to this page):
 
```mermaid
flowchart TD
    A[Client browser<br/>On-prem user]
    B[On-prem domain controller DNS<br/>Conditional forwarder for appserviceenvironment.us]
    C[Azure DNS resolver VMs<br/>Non-DC VMs inside an Azure vnet]
    D[Azure-provided DNS<br/>168.63.129.16]
    E[Private DNS Zone<br/>&lt;ase&gt;.appserviceenvironment.us]
    F[ILB private IP returned]
    A --> B --> C --> D --> E --> F
```
 
After resolution succeeds and the browser has the ILB private IP, the actual TCP traffic still has to *get* to that IP — that's the ZPA path:
 
```mermaid
flowchart LR
    U[On-prem user]
    Z[Zscaler client]
    P[ZPA cloud]
    AC[ZPA App Connector<br/>in Azure vnet]
    ILB[ASE v3 ILB<br/>Private IP]
    K[Kudu / SCM endpoint]
    U --> Z --> P --> AC --> ILB --> K
```
