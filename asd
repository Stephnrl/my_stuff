## The issue
 
A team reported that they could no longer reach the Kudu console for their Function App. The Kudu URL produced a browser DNS error rather than the usual login.
 
Symptoms:
 
- Browsing to `<app>.scm.<ase>.appserviceenvironment.us` failed to resolve.
- The Function App itself (the runtime URL) was also affected for any traffic that reached it via hostname rather than IP.
- Other Azure portal operations against the Function App worked fine because those go through the Azure management plane, not through the ASE's data plane DNS.
