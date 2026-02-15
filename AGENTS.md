# AGENTS.md — FluxCD GitOps Repository Guardrails (K3S on SBC / Edge)

This repository is the **single source of truth** for a constrained **aarch64 K3S** cluster running on **blueberry-k3s**. It is intentionally *boring*: minimal, deterministic, reproducible, and built for edge/SBC realities (limited RAM, limited IO, USB storage).

If you are a coding agent working in this repo: **do not add features because they are interesting**. Add only what is required, with the smallest possible surface area, in a way that is **repeatable from scratch**.

---

## 1) Architectural Philosophy

### GitOps-first, declarative-only
- All desired state lives in Git and is applied by Flux.
- Avoid imperative steps, local scripts, “just run this once” commands, or manual drift.
- Changes are delivered by PRs and reconciled by Flux. If it isn’t in Git, it doesn’t exist.

### Edge constraints are first-class
Assume:
- **Limited RAM** → avoid heavyweight controllers and “platforms”.
- **Limited IO / USB storage** → avoid write-amplifying components, avoid chatty observability stacks.
- **No cloud primitives** → no reliance on managed load balancers, cloud storage, cloud IAM.
- **Not HA-by-default** → do not assume multi-master HA unless explicitly introduced later.

### Minimal, reproducible, pinned
- Prefer fewer moving parts over flexibility.
- **Pin** versions where it matters:
  - Container images (tags + digests where feasible)
  - Helm chart versions
  - Flux component versions (bootstrapping toolchain)
- Determinism > convenience.

### “Boring” industry patterns
- Use mainstream Flux/Kustomize conventions and readable layout.
- Prefer stable, well-documented components.
- Avoid bespoke frameworks, meta-operators, or clever abstractions.

---

## 2) Repository Structure Expectations

This repository is structured to support:
- Multiple clusters in the future (even if you only have one today).
- Clear separation between:
  - **cluster wiring / Flux entrypoint**
  - **infrastructure components**
  - **applications**
  - **shared libraries (kustomize components), if truly needed**

### Required top-level layout
- `clusters/`  
  Cluster entrypoints and environment-specific composition. **Flux Kustomizations are anchored here.**
- `infrastructure/`  
  Platform primitives (networking, ingress, DNS, storage, certs, secrets mechanism, etc).
- `apps/`  
  Workloads and application-level components.
- `lib/` (optional, rare)  
  Kustomize components or reusable patches. Keep small and explicit.
- `.github/`  
  CI workflows and validation.

### Rules
- No manifests should be applied “by hand”. Everything must be reachable from `clusters/<cluster-name>/`.
- Avoid deep nesting. Prefer clarity over taxonomy.
- If a component is not installed by Flux, it must be documented as an explicit prerequisite (and should be minimized).

---

## 3) Flux Structure Conventions

### Cluster entrypoints
`clusters/<cluster-name>/` contains:
- Flux `GitRepository` / `OCIRepository` sources (as needed).
- Flux `Kustomization` objects that define reconciliation order and boundaries.
- Composition files that reference `infrastructure/` and `apps/`.

### Reconciliation boundaries
- One `Kustomization` per major domain (e.g., `infrastructure`, `apps`).
- Additional Kustomizations may exist for ordering-sensitive infrastructure (e.g., `crds`, `storage`, `ingress`) but **only when needed**.
- Prefer **few** Kustomizations; do not create one per app by default.

### Dependency ordering
- Use `dependsOn` in Flux Kustomizations only for genuine ordering constraints (CRDs before controllers, namespaces before workloads, secrets mechanism before secret consumers, etc).
- Do not encode fragile chains. If everything depends on everything, you’re doing it wrong.

### Health and drift
- Flux health checks must be enabled for meaningful components (controllers, ingress, critical apps).
- Prefer “fail fast” reconciliation: don’t hide broken state.

---

## 4) Namespacing Conventions

### Namespace policy
- Everything runs in an explicit namespace (no “default” namespace usage).
- `kube-system` is for K3S/Kubernetes core only. Do not deploy random add-ons there.

### Recommended namespace taxonomy (keep minimal)
- `flux-system` (reserved for Flux)
- `infrastructure-*` for platform components when justified (or a small set like `infra`, but be consistent)
- Per-app namespaces for user workloads (`app-<name>` or `<name>`), but do not explode namespaces unnecessarily

### Naming rules
- Resource names must be stable and predictable.
- Avoid environment suffixes unless you actually run multiple environments.
- Do not invent naming schemes per component—follow repo conventions.

---

## 5) Kustomize Usage

### Kustomize is the default composition tool
- Use `kustomization.yaml` to compose resources.
- Prefer **patches** and **components** over copy/paste forks, but keep complexity low.
- Avoid generating huge templated outputs. Readable diffs matter.

### Patching style
- Use strategic merge patches or JSON6902 patches when appropriate.
- Keep patches local to the component directory unless they are truly shared.
- Avoid patching across boundaries (apps patching infrastructure) unless explicitly documented.

### Generated resources
- Avoid `configMapGenerator`/`secretGenerator` unless you have a strong reason and you understand the immutability and drift implications.
- If you do generate, ensure stable naming (`disableNameSuffixHash` only when necessary and understood).

---

## 6) Helm vs Raw Manifests

### Default preference
- Prefer **raw manifests** for small/simple components.
- Prefer **HelmRelease** only when:
  - the upstream project is Helm-first,
  - the chart is maintained,
  - pinning is straightforward,
  - the chart does not hide critical configuration in unreadable values.

### Helm guardrails
- Always pin Helm chart versions.
- Keep `values` minimal and explicit; do not dump giant values.yaml files.
- Avoid post-render hacks unless unavoidable, and document why.

### Raw manifests guardrails
- Vendor upstream YAML only when necessary.
- If vendoring, pin the upstream version and record the source in a short comment header.
- Avoid “kubectl apply” style blobs. Keep resources reasonably modular.

---

## 7) Image Pinning and Supply Discipline

### Pinning rules
- Workloads must use pinned image tags. Prefer immutable tags where available.
- For critical components (controllers, ingress, DNS, storage), use digests when feasible.
- No `:latest`. No floating tags.

### Image provenance
- Prefer well-known upstream registries with multi-arch support.
- Avoid obscure images with unclear maintenance.

### Renovation policy
- Dependency update automation is allowed only if it:
  - respects pinning,
  - opens PRs (no direct pushes),
  - is predictable and reviewable.
- If introduced, it must be documented and minimal (e.g., Renovate with strict rules).

---

## 8) Upgrade Strategy (K3S, Flux, Components)

This cluster runs on **blueberry-k3s** with **pinned K3S per image release**. Treat upgrades as controlled events.

### Version skew expectations
- **K3S/Kubernetes**: upgrades must be planned; do not assume arbitrary minor jumps are safe on SBC hardware.
- **Controllers** (CNI, ingress, cert-manager, external-dns, storage): keep within supported skew relative to cluster version.
- **CRDs**: treat CRD changes as high risk. CRDs often require ordering and careful rollback planning.

### Guardrails
- Upgrades happen via PRs with:
  - explicit version bumps,
  - changelog/reference links in the PR description,
  - clear rollback notes.
- Avoid upgrading multiple major components at once unless required.
- If a component requires a multi-step upgrade (CRDs first, then controller), encode it as staged Flux Kustomizations **with documentation**.

### Rollback expectations
- Rollback must be possible by reverting Git to a known-good commit **without manual cluster surgery** whenever realistically possible.
- If rollback is not safe (common with CRD/data migrations), you must:
  - state it explicitly in docs,
  - introduce a safe upgrade path (including backups) or accept the limitation with a clear rationale.

---

## 9) Lifecycle Rules: State, Storage, and Drift

### Storage realism
- USB-attached storage and limited IO means:
  - avoid write-heavy systems by default,
  - avoid running complex distributed storage unless explicitly required later.
- Stateful workloads must be justified and documented.

### Drift control
- No manual `kubectl edit`.
- If emergency changes are applied manually, they must be backported into Git immediately (same day) with an explanation.

### Secrets
- Secrets must be managed declaratively.
- Choose one secrets strategy and keep it consistent (e.g., SOPS + age with Flux, or another explicit mechanism).
- Do not introduce multiple competing secrets systems.

---

## 10) Reproducibility From Empty Cluster

The repository must be able to bring up the full desired state from an empty cluster with:
1. A freshly installed K3S node set (explicitly configured, no auto-magic).
2. Flux installed/bootstrapped.
3. Flux reconciling this repo to converge the cluster.

### Rules
- Any prerequisites not managed by Flux must be:
  - minimal,
  - clearly documented in `README.md`,
  - stable and repeatable.
- Everything else must be expressed declaratively and applied by Flux.

---

## 11) Testing and Validation Expectations (CI-safe)

CI cannot fully emulate SBC hardware or a real K3S environment, but it **must** catch obvious breakage.

### Required CI checks (Linux runner)
- YAML validity and schema validation where possible.
- `kustomize build` for each cluster entrypoint must succeed.
- `helm template` validation for HelmReleases where feasible (or `flux build` equivalents).
- Policy checks:
  - reject `:latest`
  - ensure namespaces are explicit
  - ensure chart versions are pinned
  - ensure Flux objects are valid
- Linting:
  - `yamllint` (or equivalent)
  - `kubeconform`/`kubeval` with pinned Kubernetes schemas (and CRD schemas when possible)

### Optional higher-fidelity checks
- Lightweight ephemeral Kubernetes (e.g., kind/k3d) is allowed **only** if it remains minimal and reliable in CI.
- Do not require macOS or special runners.

### What to do when CI limitations exist
- If a component can’t be validated in CI (custom CRDs, chart-only schemas), document the limitation and add the best available static checks.

---

## 12) Explicit Non-Goals and Out-of-Scope

These are out-of-scope unless the repository owner explicitly expands scope:

- Cloud-provider integrations (managed LB, cloud storage classes, IAM bindings, etc).
- HA-by-default control plane architecture.
- Multi-cluster fleet management.
- Service mesh platforms.
- Full observability stacks (Prometheus/Grafana/Loki/Tempo) unless minimal and justified.
- Multi-tenant platform features, complex RBAC frameworks, “internal developer platforms”.
- Imperative operators that require hand-holding or post-install scripts.
- “Platform for platform’s sake” add-ons.

If you believe something in this list is required, you must:
- justify it in writing in the PR description,
- keep it minimal,
- document operational impact (RAM/CPU/IO),
- provide rollback notes.

---

## 13) Anti-Patterns (Do Not Introduce)

- Floating versions (`latest`, unpinned charts, unpinned images).
- Hidden automation that mutates cluster state outside Flux.
- Large umbrella charts with hundreds of values.
- Copy/paste divergence of the same component across directories.
- Over-abstraction: “frameworks” built inside this repo.
- “Just in case” components that are not used.
- Installing multiple tools that solve the same problem (two ingresses, two DNS systems, two secret managers, etc).
- Using the `default` namespace for anything.
- Treating this edge cluster like a cloud cluster.

---

## 14) Documentation Expectations

Documentation must match reality.

### Required docs
- `README.md` must include:
  - what this repo manages,
  - prerequisites,
  - how Flux is bootstrapped,
  - how to reconcile / troubleshoot at a high level,
  - how upgrades are performed.

### Change documentation
- When introducing a new component:
  - add a short doc note describing what it does, why it exists, and resource implications.
- When changing versions:
  - note the version bump and any required migration steps.

---

## 15) Contribution Rules for Agents

When making changes:
- Prefer the smallest PR that accomplishes the goal.
- Keep diffs readable.
- Do not introduce new dependencies without strong justification.
- Follow existing patterns; do not create a new structure because you prefer it.
- Every PR must answer:
  - What problem does this solve?
  - What is the operational cost (RAM/CPU/IO)?
  - How is it validated?
  - How do we roll it back?

If you cannot answer these, the change is not ready.

---

## 16) Principle of Least Platform

This repo is not a playground. It is an edge platform with constraints.

If a feature is not:
- required,
- minimal,
- reproducible,
- pinned,
- and operable on SBC hardware,

then it does not belong here.
