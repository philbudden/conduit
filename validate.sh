#!/bin/bash
set -e

echo "=== FluxCD GitOps Repository Validation ==="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track failures
FAILURES=0

# Function to print success
success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to print failure
failure() {
    echo -e "${RED}✗${NC} $1"
    FAILURES=$((FAILURES + 1))
}

# Function to print warning
warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo "1. Checking repository structure..."
REQUIRED_DIRS=(
    "clusters/blueberry-k3s/flux-system"
    "infrastructure/monitoring"
    "apps"
    ".github/workflows"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        success "Directory exists: $dir"
    else
        failure "Missing directory: $dir"
    fi
done

echo ""
echo "2. Checking required files..."
REQUIRED_FILES=(
    "README.md"
    "AGENTS.md"
    ".gitignore"
    ".yamllint.yaml"
    "clusters/blueberry-k3s/kustomization.yaml"
    "clusters/blueberry-k3s/flux-system/gotk-sync.yaml"
    "infrastructure/monitoring/prometheus-helmrelease.yaml"
    "infrastructure/monitoring/grafana-helmrelease.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        success "File exists: $file"
    else
        failure "Missing file: $file"
    fi
done

echo ""
echo "3. Validating YAML syntax..."
if command -v yamllint &> /dev/null; then
    if yamllint -c .yamllint.yaml clusters/ infrastructure/ 2>&1; then
        success "YAML syntax valid"
    else
        failure "YAML syntax errors found"
    fi
else
    warning "yamllint not installed, skipping YAML validation"
fi

echo ""
echo "4. Building manifests with kustomize..."
if command -v kustomize &> /dev/null; then
    if kustomize build clusters/blueberry-k3s > /dev/null 2>&1; then
        success "Cluster manifests build successfully"
    else
        failure "Cluster manifests failed to build"
    fi
    
    if kustomize build infrastructure > /dev/null 2>&1; then
        success "Infrastructure manifests build successfully"
    else
        failure "Infrastructure manifests failed to build"
    fi
else
    warning "kustomize not installed, skipping manifest build validation"
fi

echo ""
echo "5. Checking for :latest tags..."
if grep -r "image:.*:latest" clusters/ infrastructure/ apps/ 2>/dev/null; then
    failure "Found :latest image tags - all images must be pinned"
else
    success "No :latest tags found"
fi

echo ""
echo "6. Checking for explicit namespaces..."
# Check HelmReleases have namespace
MISSING_NS=$(grep -L "namespace: monitoring" infrastructure/monitoring/*-helmrelease.yaml 2>/dev/null | wc -l)
if [ "$MISSING_NS" -eq 0 ]; then
    success "All HelmReleases have explicit namespaces"
else
    failure "Found HelmRelease without namespace"
fi

echo ""
echo "7. Verifying Flux v2.4.0 references..."
if grep -q "v2.4.0" clusters/blueberry-k3s/flux-system/gotk-sync.yaml README.md; then
    success "Flux v2.4.0 referenced in documentation"
else
    warning "Flux v2.4.0 not clearly referenced"
fi

echo ""
echo "8. Checking Prometheus port configuration (avoiding Cockpit on 9090)..."
if grep -q "port: 9091" infrastructure/monitoring/prometheus-helmrelease.yaml; then
    success "Prometheus configured on port 9091 (avoiding Cockpit conflict)"
else
    failure "Prometheus port not set to 9091"
fi

echo ""
echo "=== Validation Complete ==="
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Update Git URL in clusters/blueberry-k3s/flux-system/gotk-sync.yaml"
    echo "  2. Commit and push to your repository"
    echo "  3. Bootstrap Flux: flux bootstrap github --owner=... --repository=..."
    exit 0
else
    echo -e "${RED}$FAILURES check(s) failed${NC}"
    exit 1
fi
