## Background: what changed between ASE v2 and ASE v3
 
The endpoint suffix for App Service Environment hostnames moved from the shared App Service domain to a per-ASE domain.
 
| | ASE v1 / v2 (Gov) | ASE v3 (Gov) |
|---|---|---|
| App URL | `<app>.<ase>.p.azurewebsites.us` | `<app>.<ase>.appserviceenvironment.us` |
| SCM / Kudu URL | `<app>.scm.<ase>.p.azurewebsites.us` | `<app>.scm.<ase>.appserviceenvironment.us` |
| DNS suffix to manage | `azurewebsites.us` (shared) | `<ase>.appserviceenvironment.us` (per ASE) |
 
The key implication: **every ASE v3 introduces its own DNS namespace.** If you have three ASEs named `abccloud1`, `abccloud2`, `abccloud3`, you need three Private DNS Zones. There is no longer a single shared zone you can wire up once.
 
For commercial Azure the equivalent suffixes are `azurewebsites.net` and `appserviceenvironment.net`. The behavior is the same, only the TLD differs.
 
