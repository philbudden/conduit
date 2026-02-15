# Quick Start Guide

## Initial Bootstrap (First Time)

### 1. Prerequisites Check

```bash
# Verify K3S is running
kubectl get nodes

# Verify Flux CLI is installed
flux version
# Expected: v2.4.0 or compatible

# Verify no port conflicts
# Cockpit: 9090 (pre-existing)
# Prometheus: 9091 (configured)
# Grafana: 3000 (configured)
```

### 2. Update Git Repository URL

Edit `clusters/blueberry-k3s/flux-system/gotk-sync.yaml`:

```yaml
spec:
  url: ssh://git@github.com/YOUR_ORG/YOUR_REPO  # <- Update this
```

### 3. Bootstrap Flux

**Option A: GitHub (recommended)**
```bash
export GITHUB_TOKEN=<your-token>

flux bootstrap github \
  --owner=YOUR_ORG \
  --repository=YOUR_REPO \
  --branch=main \
  --path=clusters/blueberry-k3s \
  --personal
```

**Option B: Generic Git**
```bash
flux bootstrap git \
  --url=ssh://git@github.com/YOUR_ORG/YOUR_REPO \
  --branch=main \
  --path=clusters/blueberry-k3s \
  --private-key-file=$HOME/.ssh/id_rsa
```

### 4. Verify Deployment

```bash
# Watch Flux reconciliation
watch flux get kustomizations

# Check HelmReleases
flux get helmreleases -A

# Check pods
kubectl get pods -n flux-system
kubectl get pods -n monitoring
```

### 5. Access Services

**Grafana:**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
```
- URL: http://localhost:3000
- Username: `admin`
- Password: `admin` (CHANGE IMMEDIATELY)

**Prometheus:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9091:9091
```
- URL: http://localhost:9091

---

## Daily Operations

### Check Status
```bash
# Quick health check
flux check

# Detailed status
flux get all -A
```

### Force Reconciliation
```bash
# Reconcile everything
flux reconcile kustomization flux-system --with-source

# Reconcile infrastructure only
flux reconcile kustomization infrastructure --with-source

# Reconcile specific HelmRelease
flux reconcile helmrelease -n monitoring kube-prometheus-stack
```

### View Logs
```bash
# Flux logs
flux logs --level=info --all-namespaces

# Component-specific logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
```

---

## Troubleshooting

### HelmRelease Not Installing

```bash
# Check status
kubectl describe helmrelease -n monitoring kube-prometheus-stack

# Check Helm controller logs
flux logs --kind=HelmRelease --name=kube-prometheus-stack --namespace=monitoring

# Manual reconcile with verbose output
flux reconcile helmrelease -n monitoring kube-prometheus-stack --verbose
```

### Kustomization Failing

```bash
# Describe the Kustomization
kubectl describe kustomization -n flux-system infrastructure

# Check for syntax errors locally
kustomize build infrastructure
kustomize build clusters/blueberry-k3s
```

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n monitoring

# Describe problematic pod
kubectl describe pod -n monitoring <pod-name>

# Check logs
kubectl logs -n monitoring <pod-name>

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

### Resource Issues (Raspberry Pi)

```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n monitoring

# If OOMKilled or resource pressure:
# 1. Reduce resource limits in HelmRelease values
# 2. Increase scrape intervals for Prometheus
# 3. Disable additional exporters/monitors
```

---

## Making Changes

### Update Helm Chart Version

1. Edit the HelmRelease file:
   ```bash
   vim infrastructure/monitoring/prometheus-helmrelease.yaml
   # Update spec.chart.spec.version
   ```

2. Commit and push:
   ```bash
   git add infrastructure/monitoring/prometheus-helmrelease.yaml
   git commit -m "chore: upgrade prometheus to vX.Y.Z"
   git push
   ```

3. Monitor reconciliation:
   ```bash
   flux reconcile kustomization infrastructure --with-source
   watch flux get helmreleases -A
   ```

### Add New Component

1. Create directory:
   ```bash
   mkdir -p infrastructure/my-component
   ```

2. Add manifests or HelmRelease

3. Update kustomization:
   ```bash
   echo "  - my-component" >> infrastructure/kustomization.yaml
   ```

4. Commit and verify:
   ```bash
   git add infrastructure/
   git commit -m "feat: add my-component"
   git push
   ```

---

## Emergency Procedures

### Suspend Reconciliation

```bash
# Suspend a Kustomization
flux suspend kustomization infrastructure

# Resume
flux resume kustomization infrastructure
```

### Rollback via Git

```bash
# Find the commit to rollback to
git log --oneline

# Revert to specific commit
git revert <commit-sha>
git push

# Flux will automatically reconcile to the reverted state
```

### Manual Intervention (Last Resort)

```bash
# Delete a stuck HelmRelease
kubectl delete helmrelease -n monitoring kube-prometheus-stack

# Flux will recreate it on next reconcile
# Or suspend first if you want to investigate:
flux suspend helmrelease -n monitoring kube-prometheus-stack
```

---

## Validation (Pre-Commit)

```bash
# Lint YAML
yamllint -c .yamllint.yaml .

# Build manifests
kustomize build clusters/blueberry-k3s
kustomize build infrastructure

# Check for :latest tags
grep -r "image:.*:latest" clusters/ infrastructure/ apps/
```

---

## Resource Usage Reference

**Expected baseline resource usage:**

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| Prometheus Operator | 50m | 200m | 128Mi | 256Mi |
| Prometheus | 200m | 1000m | 512Mi | 1536Mi |
| Grafana | 100m | 500m | 256Mi | 512Mi |
| **Total** | **~350m** | **~1.7 cores** | **~900Mi** | **~2.3Gi** |

**Remaining for workloads on 8GB Pi:**
- ~2 cores CPU
- ~4.5-5GB RAM (after K3S overhead)
