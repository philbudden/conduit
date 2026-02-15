# Complete Repository Structure and Content

This document provides a complete overview of the generated FluxCD GitOps repository.

## Repository Tree

```
blueberry-k3s/
 .github/
   └── workflows/
       └── validate.yaml           # CI validation workflow
 .gitignore                      # Git ignore patterns
 .yamllint.yaml                  # YAML linting configuration
 AGENTS.md                       # Architectural guardrails (pre-existing)
 LICENSE                         # License file (pre-existing)
 README.md                       # Main documentation
 QUICKSTART.md                   # Quick reference guide
 apps/
   └── README.md                   # Placeholder for application workloads
 clusters/
   └── blueberry-k3s/              # Cluster entrypoint
       ├── flux-system/
       │   ├── gotk-components.yaml # Flux controllers (placeholder for bootstrap)
       │   ├── gotk-sync.yaml       # GitRepository and root Kustomization
       │   └── kustomization.yaml   # Flux system composition
       ├── infrastructure.yaml      # Infrastructure Kustomization
 kustomization.yaml       # Root cluster composition       
 infrastructure/
    ├── kustomization.yaml          # Infrastructure composition
    └── monitoring/
        ├── namespace.yaml           # monitoring namespace
        ├── helm-repository.yaml     # Prometheus Community & Grafana Helm repos
        ├── prometheus-helmrelease.yaml # kube-prometheus-stack HelmRelease
        ├── grafana-helmrelease.yaml    # Grafana HelmRelease
        └── kustomization.yaml       # Monitoring composition
```

## Key Design Decisions

### 1. Flux Structure
- **Single cluster**: `blueberry-k3s` (structure supports future clusters)
- **Single infrastructure Kustomization**: Simplified reconciliation
- **No apps Kustomization yet**: Added when first application is deployed

### 2. Monitoring Stack
- **kube-prometheus-stack v67.4.0**: Prometheus Operator + Prometheus
  - Port 9091 (Cockpit on 9090)
  - Disabled: Alertmanager, node-exporter, kube-state-metrics
  - 60s scrape intervals (edge-optimized)
  - No persistence (emptyDir)
  - 7-day retention / 4GB limit

- **Grafana v8.7.2** (image 11.4.0):
  - Pre-configured Prometheus datasource
  - Default dashboards: K8s cluster overview, pod monitoring
  - No persistence (emptyDir)
  - Default credentials: admin/admin

### 3. Resource Allocation
- **Total CPU requests**: ~350m
- **Total CPU limits**: ~1.7 cores
- **Total memory requests**: ~900Mi
- **Total memory limits**: ~2.3Gi
- **Remaining for workloads**: ~2 cores CPU, ~4.5GB RAM

### 4. Edge Optimizations
- Conservative resource limits
- Reduced scrape intervals (60s vs 15-30s default)
- Disabled write-heavy components (persistence, alertmanager)
- Disabled high-cardinality exporters
- Single-replica deployments

## Pinned Versions

| Component | Version | Notes |
|-----------|---------|-------|
| Flux | v2.4.0 | Bootstrap target |
| Kustomize | 5.5.0 | CI validation |
| kube-prometheus-stack chart | 67.4.0 | Pinned Helm chart |
| Grafana chart | 8.7.2 | Pinned Helm chart |
| Grafana image | 11.4.0 | Explicitly pinned |

**No `:latest` tags**: All images are pinned via chart defaults or explicit overrides.

## Reconciliation Flow

```
GitRepository (flux-system)
  ↓
Kustomization (flux-system)
  ├── clusters/blueberry-k3s/flux-system/
  ├── clusters/blueberry-k3s/infrastructure.yaml
  └── clusters/blueberry-k3s/kustomization.yaml
      ↓
Kustomization (infrastructure)
  └── infrastructure/
      └── monitoring/
          ├── namespace.yaml (monitoring NS)
          ├── helm-repository.yaml (Helm repos)
          ├── prometheus-helmrelease.yaml (Prometheus)
          └── grafana-helmrelease.yaml (Grafana)
```

## CI Validation

GitHub Actions workflow validates:
1. YAML syntax (yamllint)
2. Manifest buildability (kustomize build)
3. Kubernetes schema (kubeconform)
4. No `:latest` tags
5. Explicit namespaces

## Bootstrap Requirements

### Before Bootstrap
1. K3S installed on blueberry-k3s
2. kubectl access configured
3. Flux CLI v2.4.0 installed
4. Git repository created and accessible
5. Update GitRepository URL in `clusters/blueberry-k3s/flux-system/gotk-sync.yaml`

### Bootstrap Command
```bash
flux bootstrap github \
  --owner=YOUR_ORG \
  --repository=YOUR_REPO \
  --branch=main \
  --path=clusters/blueberry-k3s \
  --personal
```

### Post-Bootstrap Verification
```bash
flux get kustomizations
flux get helmreleases -A
kubectl get pods -n flux-system
kubectl get pods -n monitoring
```

## Security Considerations

 **Important**:
- Default Grafana credentials are `admin/admin` - **change immediately**
- No TLS/ingress configured - services are ClusterIP only
- No secrets encryption (SOPS) configured yet
- No RBAC policies beyond Flux defaults

For production use:
1. Enable SOPS for secrets encryption
2. Add ingress with TLS (cert-manager + Let's Encrypt)
3. Configure OAuth/SSO for Grafana/Prometheus
4. Implement NetworkPolicies

## Compliance with AGENTS.md

 **GitOps-first, declarative-only**: All state in Git, Flux-reconciled
 **Edge constraints**: Resource limits, reduced intervals, no persistence
 **Minimal, reproducible, pinned**: All versions pinned, no `:latest`
 **Boring patterns**: Standard Flux/Kustomize layout
 **Proper structure**: clusters/, infrastructure/, apps/ separation
 **Reconciliation boundaries**: Single infrastructure Kustomization
 **Explicit namespaces**: monitoring namespace, no default usage
 **Kustomize composition**: Clear resource references
 **Helm guardrails**: Pinned charts, minimal values
 **Image pinning**: No floating tags
 **Reproducible from empty cluster**: Bootstrap + reconcile = converged state
 **CI validation**: YAML lint, kustomize build, schema validation, policy checks
 **No anti-patterns**: No `:latest`, no hidden automation, no over-abstraction

## Next Steps

1. **Bootstrap Flux** on the cluster
2. **Change Grafana password** after first login
3. **Verify monitoring**: Check Prometheus targets, Grafana datasource
4. **Add persistence** (optional): Create PVs for Prometheus/Grafana if needed
5. **Enable exporters** (optional): node-exporter, kube-state-metrics if resources allow
6. **Add ingress** (future): For external access with TLS
7. **Add applications**: Create components under `apps/` as needed

## Validation Commands

```bash
# Local validation before commit
yamllint -c .yamllint.yaml .
kustomize build clusters/blueberry-k3s
kustomize build infrastructure
grep -r "image:.*:latest" clusters/ infrastructure/ apps/

# After bootstrap
flux check
flux get kustomizations
flux get helmreleases -A
kubectl get pods -A

# Resource usage
kubectl top nodes
kubectl top pods -n monitoring
```

## Support and Troubleshooting

See [QUICKSTART.md](./QUICKSTART.md) for:
- Common operations
- Troubleshooting procedures
- Emergency procedures
- Resource usage reference

See [README.md](./README.md) for:
- Detailed component documentation
- Upgrade procedures
- Rollback procedures
- Contributing guidelines

See [AGENTS.md](./AGENTS.md) for:
- Architectural constraints
- Design philosophy
- Anti-patterns to avoid
- Contribution rules
