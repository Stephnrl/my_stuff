# Actions Runner Controller: Modern (Scale Set) Architecture

> A field guide for migrating from the legacy `actions.summerwind.dev` controller (Summerwind) to the modern `actions.github.com` controller (GitHub-managed Scale Sets).

---

## The mental model: legacy vs modern

In **Summerwind** (legacy `actions.summerwind.dev`), ARC behaves like a typical Kubernetes operator that mimics a Deployment / ReplicaSet pattern. You give it a `RunnerDeployment`, optionally a `HorizontalRunnerAutoscaler`, and ARC reacts to GitHub webhooks (or polling) to scale runner pods. ARC itself fetches a registration token, injects it into the pod, and the pod self-registers as a runner. There is no concept of a "scale set" on the GitHub side — GitHub just sees a bunch of self-hosted runners.

In **Modern** (`actions.github.com`, installed via the `gha-runner-scale-set` Helm charts), GitHub itself has a native API concept called a **Runner Scale Set**. ARC registers your `AutoscalingRunnerSet` as a scale set on GitHub. Then a tiny dedicated **listener pod** holds a long-poll connection open to GitHub's Actions Service. When a workflow's `runs-on:` matches your scale set's name, GitHub pushes a "I have N jobs queued" message down that long-poll, and the listener tells Kubernetes to scale runner pods accordingly. JIT (just-in-time) tokens replace the long-lived registration tokens — each runner pod gets a one-shot config that only works once.

---

## The four CRDs (yes, all of them are CRDs)

| CRD | Analogous to | What it represents |
|---|---|---|
| `AutoscalingRunnerSet` (ARS) | Deployment | Top-level, user-facing. You write this (via Helm). Defines the pod template, min/max runners, GitHub URL, secret reference. |
| `AutoscalingListener` (AL) | (no K8s analog) | One per ARS. Owns the listener Pod that long-polls GitHub. |
| `EphemeralRunnerSet` (ERS) | ReplicaSet | One per ARS. Holds the current desired replica count and creates `EphemeralRunner` children. |
| `EphemeralRunner` (ER) | Pod (sort of) | One per actual runner. Wraps the Pod with extra lifecycle / finalizer logic for GitHub deregistration. |

Ownership is hierarchical via `ownerReferences`: `ARS` owns `AL` and `ERS`; `ERS` owns multiple `ER`s; each `ER` owns its actual runner Pod. Delete the `ARS` and the whole tree cascades.

---

## The four controllers (all live inside one Pod)

The "controller manager" is a single Deployment installed by the `gha-runner-scale-set-controller` Helm chart. Inside that one pod, four reconciler loops run:

### `AutoscalingRunnerSetReconciler`
Watches `AutoscalingRunnerSet`. On create it:
1. Calls GitHub's API to register the scale set and gets back a scale set ID.
2. Creates the child `AutoscalingListener` and `EphemeralRunnerSet`.

It also handles update strategies (`immediate` vs `eventual`) when the pod template changes.

### `AutoscalingListenerReconciler`
Watches `AutoscalingListener`. Creates the listener Pod plus its ServiceAccount / Role / RoleBinding. The listener pod's RBAC is scoped tightly: it can only `patch` the `spec.replicas` of its own `EphemeralRunnerSet`.

### `EphemeralRunnerSetReconciler`
Watches `EphemeralRunnerSet.spec.replicas` and the status of its child `EphemeralRunner`s. If `pending + running < replicas`, it creates more `EphemeralRunner` CRs. If terminal-state runners exist, it cleans them up.

### `EphemeralRunnerReconciler`
Watches `EphemeralRunner`. Calls GitHub's API to obtain a **JIT config token** for this specific runner, creates the runner Pod with that token baked into a secret, and uses finalizers to ensure the runner is deregistered from GitHub before the K8s Pod is deleted. Implements exponential backoff (0 / 5 / 10 / 20 / 40 / 80s, max 5 failures) for pod failures.

---

## Architecture diagram

```mermaid
flowchart TD
    GH["GitHub Actions Service<br/><i>(External SaaS)</i>"]

    subgraph K8S["Kubernetes Cluster"]
        CM["ARC Controller Manager<br/><i>(4 reconcilers)</i>"]
        ARS["AutoscalingRunnerSet<br/><i>Top-level CRD (Helm)</i>"]
        AL["AutoscalingListener<br/><i>Manages listener pod</i>"]
        ERS["EphemeralRunnerSet<br/><i>Holds spec.replicas</i>"]
        ER["EphemeralRunner<br/><i>One per runner</i>"]
        LP["Listener Pod<br/><i>Long-polls GitHub</i>"]
        RP["Runner Pod<br/><i>Runs one job, exits</i>"]
    end

    ARS -->|owns| AL
    ARS -->|owns| ERS
    AL -->|creates| LP
    ERS -->|owns| ER
    ER -->|creates| RP

    LP <-->|long-poll| GH
    LP -->|patches replicas| ERS
    RP -.->|JIT register| GH

    CM -.->|reconciles| ARS
    CM -.->|reconciles| AL
    CM -.->|reconciles| ERS
    CM -.->|reconciles| ER
```

---

## The data flow, step by step

### Boot time (one-time, when you `helm install` the scale set)

1. You apply the `gha-runner-scale-set` chart, which creates an `AutoscalingRunnerSet` CR in your namespace.
2. The **ARS reconciler** sees it, calls GitHub's Actions Service API, and registers a Runner Scale Set under that name. GitHub returns a scale set ID.
3. The ARS reconciler creates an `AutoscalingListener` CR and an `EphemeralRunnerSet` CR (initially with `spec.replicas = minRunners`).
4. The **Listener reconciler** sees the new `AutoscalingListener` and creates the listener Pod plus a dedicated ServiceAccount with a Role that allows it to `patch` exactly one resource: its `EphemeralRunnerSet`.
5. The listener Pod starts, authenticates to GitHub (using the PAT or GitHub App credentials from the Secret), and opens a **long-poll HTTPS connection** to the Actions Service.

### Runtime (every time a workflow runs)

6. A developer pushes code. A workflow has `runs-on: my-scale-set-name`. GitHub queues the job for that scale set.
7. GitHub responds to the open long-poll with a message: "you have N pending jobs."
8. The listener Pod computes the new desired replicas and `kubectl patch`es `EphemeralRunnerSet.spec.replicas`. (This is the *only* thing it can do to the cluster — its RBAC is intentionally tiny.)
9. The **ERS reconciler** sees `spec.replicas` is higher than current and creates that many new `EphemeralRunner` CRs.
10. The **ER reconciler** for each new `EphemeralRunner` calls GitHub's API to get a **JIT config token** (a one-shot, runner-specific credential), stores it in a Secret, and creates the actual runner Pod with that Secret mounted.
11. The runner Pod starts, uses the JIT config to register itself with GitHub as a runner, picks up its assigned job, and runs it.
12. When the job finishes, the runner binary exits (it's ephemeral — single job, no reuse). The Pod terminates.
13. The **ER reconciler** sees the Pod terminated, confirms deregistration with GitHub, removes the finalizer, and the `EphemeralRunner` is deleted. The **ERS reconciler** notices the count dropped and may recreate one to maintain `minRunners`, or scale down further if the listener has lowered `spec.replicas`.

---

## Why "listener pod" is the conceptual leap

In Summerwind, scaling logic lives in the controller and is triggered by webhook events or polling. In modern ARC, **the listener pod IS the scaler**. It is a dedicated, lightweight Pod whose entire job is to hold one long-poll connection and translate GitHub's "job queue depth" signal into a `spec.replicas` patch.

The ARC controller manager doesn't decide *when* to scale — it just makes sure the listener Pod exists and the resulting `EphemeralRunner` CRs become Pods. That separation is why the new system is:

- **Cheaper on the GitHub API** — no polling, no token churn.
- **Free of cert-manager** — no admission webhooks needed for the scaling decision.
- **More reliable at scale** — no missed webhook events.

---

## Feature comparison

| Feature | Legacy (`actions.summerwind.dev`) | Modern (`actions.github.com`) |
|---|---|---|
| **Scaling trigger** | Webhooks (Workflow Job) or polling | Long-polling via `AutoscalingListener` |
| **Runner registration** | Registration tokens (short-lived) | JIT (Just-In-Time) config tokens |
| **Persistence** | Supported via `RunnerSet` | Ephemeral by design (`EphemeralRunner`) |
| **API rate limits** | High (frequent polling / token calls) | Low (long-polling reduces API overhead) |
| **Dependency** | Requires `cert-manager` for webhooks | No `cert-manager` required |
| **Update strategy** | Manual or rolling | `immediate` or `eventual` (PatchID based) |

---

## SME-level gotchas to internalize

### 1. `runs-on:` matches the scale set name, not labels
In your workflows, `runs-on:` must match the **name of the `AutoscalingRunnerSet`**, not a label on the runner itself. This is the single most common migration bug.

```yaml
# .github/workflows/build.yml
jobs:
  build:
    runs-on: my-scale-set-name   # ← must equal the AutoscalingRunnerSet name
```

### 2. Chart installation scope
- The **controller chart** (`gha-runner-scale-set-controller`) is installed **once per cluster**.
- The **scale-set chart** (`gha-runner-scale-set`) is installed **once per scale set**, each typically in its own namespace.
- Multiple scale sets share the controller manager but each gets its own listener pod and runner pool.

### 3. Two finalizers on `EphemeralRunner`
`ephemeralRunnerFinalizerName` and `ephemeralRunnerActionsFinalizerName` ensure GitHub deregistration happens *before* the K8s Pod is garbage-collected. If you ever see runners stuck in `Terminating`, it is almost always the Actions-side finalizer waiting on GitHub.

### 4. Update strategy can over-provision
`updateStrategy: immediate` (default) will over-provision during a rolling update of the runner spec — the listener gets recreated immediately and may scale up new-spec runners before old-spec jobs finish. Set `eventual` if you need clean drains.

### 5. Credentials never reach runner pods
The PAT or GitHub App credentials only live in the controller and the `EphemeralRunner` reconciler — they are **never injected into runner pods**. Runner pods only ever see their JIT token, which is single-use and scoped to one job. That's a meaningful security improvement over legacy.

### 6. Resource translation when migrating

| Legacy field | Modern field |
|---|---|
| `spec.template.spec.repository` | `spec.githubConfigUrl` |
| `spec.template.spec.organization` | `spec.githubConfigUrl` |
| `spec.template.spec.labels` | Managed via scale set name in GitHub |
| `spec.replicas` | `spec.minRunners` / `spec.maxRunners` |

---

## Further reading

- DeepWiki: [Migration Guide (Legacy to Modern)](https://deepwiki.com/actions/actions-runner-controller/8-migration-guide-(legacy-to-modern))
- DeepWiki: [Modern Controllers (actions.github.com)](https://deepwiki.com/actions/actions-runner-controller/3.2-modern-controllers-(actions.github.com))
- DeepWiki: per-controller deep dives for `AutoscalingRunnerSet`, `AutoscalingListener`, `EphemeralRunnerSet`, and `EphemeralRunner` — the actual Go code paths live there.
- GitHub docs: [About Actions Runner Controller](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/about-actions-runner-controller)
