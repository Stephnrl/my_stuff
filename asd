Runner groups ≠ scale sets. In GitHub's model, a runner group is an access-control container at the org/enterprise level ("which repos can target these runners") — it exists on GitHub's side. A scale set is the ARC-side Kubernetes resource (AutoscalingRunnerSet) that workflows target by name via runs-on:. A scale set can optionally be placed into a runner group for access control, but they aren't the same object. So what you're actually describing is two scale sets — probably called arc-enterprise-prod and arc-enterprise-nonprod — and optionally you put them in matching runner groups for access scoping. Totally normal pattern and exactly what the modern API is designed for.
Can workflows target either? Yes, and cleanly. With the new API each scale set defines its own runs-on label:
yamljobs:
  build-runner-image:
    runs-on: arc-enterprise-nonprod   # or -prod
No matrix labels, no self-hosted, linux, x64, scale-set-enterprise multi-label acrobatics like the Summerwind days. One name, one scale set.
On "can the prod scale set build its own image?" Technically yes, and you're right that ephemeral pods make this clean — the runner that runs docker buildx bake --push terminates when the job ends, and the next pod spawned by the controller pulls whatever image the AutoscalingRunnerSet spec references. There's no "updating itself while running" problem. Performance is fine: it's just another build job on a pod that gets torn down.
But there's one real hazard: the bootstrap loop. If you use image: myacr.azurecr.io/arc-runner:dotnet8-latest with imagePullPolicy: Always, and a build pushes a broken :latest, then every subsequent pod in that scale set comes up broken — including the pod you'd need to spawn to build the fix. You've just locked yourself out of the scale set. I've watched people recover from this by hand-editing the AutoscalingRunnerSet to point at a known-good SHA tag while swearing a lot. So:
The safer pattern, which I'd push you toward:

Build the image from arc-enterprise-nonprod. Both prod and nonprod have the same tooling installed, so nonprod is perfectly capable, and if a build poisons its own image the blast radius is the nonprod scale set only. Prod keeps humming on whatever tag it's pinned to.
Push to ACR with an immutable tag — SHA-based, like arc-runner:dotnet8-a3f9c12, never :latest in the scale set spec.
The AutoscalingRunnerSet manifest lives in Git (Flux/Argo/Helm). Promoting a new image = PR that bumps the tag. That PR triggers the prod rollout; next pod spawn pulls the new tag; old pods finish their jobs and drain naturally. No manual kubectl.
Keep :latest as a convenience tag in ACR for humans, but don't point the scale set at it.

This turns your 2-week patch cadence into: scheduled workflow → build on nonprod → push immutable tag + :latest → bump automated PR against the prod AutoscalingRunnerSet → merge after CI / manual gate → prod picks up on next pod spawn. No performance impact anywhere, no circular hazard, and rollback is a one-line git revert.
Two more things that matter for the cadence:

Retain the last few image tags in ACR (ACR retention policy — e.g., keep last 10 dotnet8-* tags). When you need to rollback, it's a tag change, not a rebuild.
Use OIDC federation (workload identity) from the runners to Azure, not a stored SP secret. With ARC on AKS you get workload identity for free and it's a much better posture than mounting a secret.
Build for both variants on the same schedule — because the bake matrix shares cache, building dotnet-8 and dotnet-10 together on the 2-week cron is only marginally slower than one alone, and keeps them version-synchronized.

One edge case worth naming: if arc-enterprise-nonprod is ever scaled to zero and there's no warm pod, the first build after a long idle can be slow because the controller has to spin a pod and pull the (large) runner image. Not a correctness issue, just don't be surprised if the first Monday-morning build looks sluggish. minRunners: 1 on nonprod fixes it if you care.
