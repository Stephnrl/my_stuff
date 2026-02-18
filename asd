    # Optional: keep VS2019 / MSBuild 16 side-by-side for legacy pipelines
    # Uncomment if needed
    # - role: vs_buildtools
    #   vars:
    #     vs_install_label: "vs2019"
    #     vs_installer_url: "https://aka.ms/vs/16/release/vs_buildtools.exe"
    #     vs_version_major: 16
    #     vs_workloads:
    #       - Microsoft.VisualStudio.Workload.MSBuildTools
    #       - Microsoft.VisualStudio.Workload.NetCoreBuildTools
    #     vs_components:
    #       - Microsoft.Net.Component.4.8.SDK
    #       - Microsoft.VisualStudio.Component.NuGet.BuildTools
