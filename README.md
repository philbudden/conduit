# blueberry-k3s GitOps Repository

This repository is the **single source of truth** for the `blueberry-k3s` K3S cluster running on Raspberry Pi 4.

**Architecture Philosophy**: Minimal, deterministic, reproducible GitOps for edge/SBC environments. See [AGENTS.md](./AGENTS.md) for detailed guardrails and constraints.

---

## Cluster Information

- **Cluster Name**: `blueberry-k3s`
- **Hardware**: Raspberry Pi 4 (8GB RAM)
- **Architecture**: aarch64
- **Kubernetes**: K3S (single server node, may scale to +2 agent nodes)
- **Storage**: USB-attached
- **GitOps**: FluxCD v2.4.0

---

## Repository Structure

```
.
├── clusters/
│   └── blueberry-k3s/          # Cluster-specific entrypoint
│       ├── flux-system/        # Flux controllers and GitRepository source
│       ├── infrastructure.yaml # Infrastructure Kustomization
│       └── kustomization.yaml  # Root composition
├── infrastructure/
│   └── monitoring/             # Prometheus + Grafana observability stack
├── apps/                       # Application workloads (empty initially)
├── .github/
│   └── workflows/              # CI validation (lint, kubeconform, policy checks)
└── AGENTS.md                   # Repository guardrails and architectural philosophy
```

---

## Prerequisites

Before bootstrapping Flux, ensure:

1. **K3S installed** on `blueberry-k3s`
   - K3S should be configured with your desired settings
   - `kubectl` access to the cluster

2. **Flux CLI installed** (v2.4.0)
   ```bash
   curl -s https://fluxcd.io/install.sh | sudo bash
   ```

3. **Git repository access**
   - SSH key or personal access token configured
   - Write access to this repository

4. **No port conflicts**
   - Cockpit runs on port 9090
   - Prometheus configured to use port 9091
   - Grafana uses port 3000

---

## Bootstrap Instructions

### First-Time Setup

1. **Fork or clone this repository**

2. **Update the GitRepository URL** in `clusters/blueberry-k3s/flux-system/gotk-sync.yaml`:
   ```yaml
   spec:
     url: ssh://git@github.com/YOUR_ORG/YOUR_REPO
   ```

3. **Bootstrap Flux**:
   ```bash
   flux bootstrap git \
     --url=ssh://git@github.com/YOUR_ORG/YOUR_REPO \
     --branch=main \
     --path=clusters/blueberry-k3s \
     --private-key-file=/path/to/ssh/key
   ```

   Or, if using GitHub directly:
   ```bash
   flux bootstrap github \
     --owner=YOUR_ORG \
     --repository=YOUR_REPO \
     --branch=main \
     --path=clusters/blueberry-k3s \
     --personal
   ```

4. **Verify reconciliation**:
   ```bash
   flux get kustomizations
   flux get helmreleases -A
   ```

5. **Access Grafana**:
   ```bash
   kubectl port-forward -n monitoring svc/grafana 3000:80
   ```
   - URL: http://localhost:3000
   - Default credentials: `admin` / `admin` (change immediately)

6. **Access Prometheus** (optional):
   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9091:9091
   ```
   - URL: http://localhost:9091

---

## Deployed Components

### Infrastructure

#### Monitoring (`infrastructure/monitoring/`)

**Prometheus (kube-prometheus-stack v67.4.0)**:
- Prometheus Operator + Prometheus server
- Port: 9091 (to avoid Cockpit conflict on 9090)
- Retention: 7 days / 4GB
- Scrape interval: 60s (tuned for edge IO constraints)
- Resource limits: 1 CPU / 1.5GB RAM
- **Disabled**: Alertmanager, node-exporter, kube-state-metrics (can enable later)
- **No persistence** (emptyDir) - can be added later if needed

**Grafana (v8.7.2 / image 11.4.0)**:
- Pre-configured Prometheus datasource
- Default dashboards: Kubernetes cluster overview, pod monitoring
- Resource limits: 500m CPU / 512MB RAM
- **No persistence** (emptyDir)
- Default credentials: `admin` / `admin` ⚠️ **Change after first login**

**Resource Usage** (approximate):
- Total CPU: ~1.3 cores (requests) / ~2 cores (limits)
- Total RAM: ~900MB (requests) / ~2.3GB (limits)
- Acceptable for 8GB Raspberry Pi 4 with headroom for workloads

---

## Operations

### Check Flux Status

```bash
# Overall health
flux check

# Reconciliation status
flux get sources git
flux get kustomizations

# HelmRelease status
flux get helmreleases -A
```

### Force Reconciliation

```bash
# Reconcile infrastructure
flux reconcile kustomization infrastructure --with-source

# Reconcile specific HelmRelease
flux reconcile helmrelease -n monitoring kube-prometheus-stack
flux reconcile helmrelease -n monitoring grafana
```

### View Logs

```bash
# Flux controller logs
flux logs --level=error --all-namespaces

# Prometheus operator logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator

# Grafana logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
```

### Troubleshooting

**HelmRelease stuck or failing**:
```bash
kubectl describe helmrelease -n monitoring kube-prometheus-stack
kubectl describe helmrelease -n monitoring grafana
```

**Prometheus not scraping**:
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9091:9091
# Visit http://localhost:9091/targets
```

**Grafana datasource issues**:
- Verify Prometheus service name: `kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9091`
- Check Grafana datasource config in Grafana UI

---

## Upgrade Strategy

All upgrades must be done via Git commits (PRs recommended).

### Upgrading Helm Charts

1. Update chart version in `infrastructure/monitoring/*-helmrelease.yaml`
2. Review upstream changelog
3. Test reconciliation: `flux reconcile helmrelease -n monitoring <name>`
4. Monitor for errors: `flux logs`

### Upgrading Flux

```bash
# Check current version
flux version

# Upgrade Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Upgrade controllers
flux install --export > clusters/blueberry-k3s/flux-system/gotk-components.yaml
git add clusters/blueberry-k3s/flux-system/gotk-components.yaml
git commit -m "chore: upgrade Flux to vX.Y.Z"
git push
```

---

## Rollback

To rollback to a previous state:

```bash
# Find known-good commit
git log --oneline

# Revert to commit
git revert <commit-sha>
git push

# Or hard reset (use with caution)
git reset --hard <commit-sha>
git push --force
```

Flux will reconcile to the reverted state automatically.

**Note**: CRD changes and stateful components may not rollback cleanly. Always test upgrades in a non-production environment first.

---

## Adding New Components

1. **Create component directory** under `infrastructure/` or `apps/`
2. **Add manifests or HelmRelease**
3. **Update parent kustomization.yaml** to reference new component
4. **Commit and push**
5. **Verify reconciliation**: `flux get kustomizations`

Example:
```bash
mkdir -p infrastructure/ingress
# Add manifests...
echo "  - ingress" >> infrastructure/kustomization.yaml
git add infrastructure/
git commit -m "feat: add ingress-nginx"
git push
```

---

## CI/CD Validation

Pull requests are automatically validated with:
- **yamllint**: YAML syntax and formatting
- **kustomize build**: Ensure manifests build successfully
- **kubeconform**: Kubernetes schema validation
- **Policy checks**: No `:latest` tags, explicit namespaces

See `.github/workflows/validate.yaml` for details.

---

## Resource Constraints and Edge Considerations

This cluster runs on a **Raspberry Pi 4** with **limited resources**:

- **RAM**: 8GB total (K3S + system overhead ~1-2GB)
- **CPU**: 4 cores (ARM Cortex-A72)
- **Storage**: USB-attached (limited IO bandwidth, avoid write-heavy workloads)

**Design Principles**:
- Conservative resource requests/limits
- Minimal scrape intervals for Prometheus
- No persistent storage by default (can be added later)
- Disabled non-essential exporters and controllers
- Single-replica deployments (no HA)

See [AGENTS.md](./AGENTS.md) for full architectural constraints.

---

## Security Notes

⚠️ **Default Grafana credentials** are `admin` / `admin`. **Change these immediately** after first login.

For production use, consider:
- Implementing SOPS encryption for secrets (see Flux SOPS guide)
- Setting up proper ingress with TLS
- Configuring authentication for Prometheus/Grafana
- Enabling RBAC policies

---

## Contributing

See [AGENTS.md](./AGENTS.md) for contribution guidelines and architectural guardrails.

**Key principles**:
- Keep changes minimal and justified
- Pin all versions (charts, images)
- Test in CI before merging
- Document resource impact
- Ensure reproducibility

---

## License

See [LICENSE](./LICENSE)