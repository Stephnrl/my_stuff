vs_workloads:
  - Microsoft.VisualStudio.Workload.MSBuildTools
  - Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools
  # Removed: NetCoreBuildTools — out of support, replaced by NetCore components below

vs_components:
  - Microsoft.Net.Component.4.8.SDK
  - Microsoft.Net.Component.4.8.TargetingPack
  - Microsoft.VisualStudio.Component.NuGet.BuildTools
  - Microsoft.NetCore.Component.Runtime.8.0           # explicit .NET 8 runtime
  - Microsoft.NetCore.Component.SDK                   # current .NET SDK (8+9 in VS2022)
