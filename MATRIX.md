# Matrix Deployment Guide

This guide configures the Matrix stack — **Synapse** (homeserver), **Element Web** (client), and **PostgreSQL** (database) — already present in `apps/matrix/` and makes it production-ready on your K3s cluster.

**This repository is public.** Credentials must never appear in plain text in a Git commit. This guide uses **SOPS + age** as the mandatory secret management path. SOPS encrypts secret files before they reach Git; Flux decrypts them inside the cluster at apply time. No secrets are ever visible in the repository.

If you are not familiar with SOPS or age, everything you need is explained below — no prior knowledge assumed.

---

## How secrets are kept safe

Two files in `apps/matrix/` contain sensitive values:

- `apps/matrix/matrix-secrets.yaml` — the Kubernetes `Secret` holding PostgreSQL credentials and Synapse cryptographic keys.
- `apps/matrix/synapse-config.yaml` — the `ConfigMap` containing the full Synapse `homeserver.yaml`, which embeds the database password and cryptographic secrets.

Both files are encrypted with SOPS using an **age** key before being committed to Git. Anyone who views the repository sees only ciphertext. The **private** age key lives only in the cluster (as a Kubernetes Secret in `flux-system`) and on your workstation. Flux's `kustomize-controller` holds that private key and silently decrypts the files at reconcile time.

```
Your workstation                    Git (public)           Cluster
─────────────────                   ─────────────          ───────────────────────────
Generate secrets                    Encrypted blobs        kustomize-controller
Fill in plain-text files   ──────►  (safe to push)  ────►  decrypts with age private key
Encrypt with SOPS + age key         No plain text          Applies real Secret + ConfigMap
```

---

## Prerequisites

Before starting, check that you have:

- `kubectl` access to the cluster: `kubectl get nodes` should return a node.
- Flux bootstrapped and reconciling: `flux get kustomizations` should show `READY: True` for `flux-system` and `infrastructure`.
- Write access to this Git repository.

You also need two tools installed on the workstation you use to manage the cluster. Install them now if missing:

**age** (encryption tool):
```bash
# Linux (amd64 or arm64)
curl -Lo age.tar.gz https://github.com/FiloSottile/age/releases/latest/download/age-v1.2.0-linux-amd64.tar.gz
tar -xf age.tar.gz && sudo mv age/age age/age-keygen /usr/local/bin/

# macOS
brew install age

# Verify
age --version
```

**sops** (secret file encryption CLI):
```bash
# Linux (amd64 or arm64)
curl -Lo sops https://github.com/getsops/sops/releases/latest/download/sops-v3.9.4.linux.amd64
chmod +x sops && sudo mv sops /usr/local/bin/

# macOS
brew install sops

# Verify
sops --version
```

---

## Step 1 — Generate your age keypair

age uses asymmetric cryptography: you encrypt with the **public key**, Flux decrypts with the **private key**. Generate a keypair now.

```bash
age-keygen -o age.key
```

The output looks like:
```
Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

Note the public key — you will use it throughout the rest of this guide. It is safe to share. The private key is in `age.key` — never commit this file.

Add it to `.gitignore` immediately:
```bash
echo "age.key" >> .gitignore
git add .gitignore
```

---

## Step 2 — Store the private key in the cluster

Flux needs access to the private key to decrypt secrets at reconcile time. Store it as a Kubernetes Secret in the `flux-system` namespace. This Secret is applied out-of-band (directly via kubectl) and is never stored in Git.

```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.key
```

Verify it was created:
```bash
kubectl get secret sops-age -n flux-system
# Expected: NAME       TYPE     DATA   AGE
#           sops-age   Opaque   1      <just now>
```

> **Keep `age.key` safe.** This file is the only way to decrypt secrets if you need to re-create the cluster. Store it in a password manager or encrypted offline backup. If it is lost, you must regenerate all secrets and re-encrypt.

---

## Step 3 — Find your K3s node IP address

```bash
kubectl get nodes -o wide
```

Look at the `INTERNAL-IP` column. This is the IP address that browsers and Matrix apps will use to reach Synapse and Element. Write it down — you will use it in Step 5.

Example: `192.168.1.100`. All examples in this guide use this IP; substitute your real IP throughout.

---

## Step 4 — Choose your `server_name`

`server_name` is the **Matrix identity domain** — the part after the colon in Matrix IDs like `@alice:example.com`. This value is permanently embedded in every user account and room created on this server. **It cannot be changed after the first user or room exists** without destroying the database and starting over.

Choose it now, before anything is deployed:

| Scenario | Recommended value |
|---|---|
| Home lab, no public DNS | Use the node IP: `192.168.1.100` |
| Own a domain, will configure DNS | Your domain: `matrix.yourdomain.com` |

Using the node IP is the simplest option for a home network and requires no DNS changes.

---

## Step 5 — Generate secrets

The Matrix stack requires four independent cryptographic secrets. Generate each one separately:

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"   # 1. POSTGRES_PASSWORD
python3 -c "import secrets; print(secrets.token_hex(32))"   # 2. SYNAPSE_MACAROON_SECRET_KEY
python3 -c "import secrets; print(secrets.token_hex(32))"   # 3. SYNAPSE_REGISTRATION_SHARED_SECRET
python3 -c "import secrets; print(secrets.token_hex(32))"   # 4. SYNAPSE_FORM_SECRET
```

Each command produces a 64-character hex string. Label them clearly — you need all four in the next step, and value 1 (`POSTGRES_PASSWORD`) is also needed in Step 7.

---

## Step 6 — Populate `apps/matrix/matrix-secrets.yaml`

Open `apps/matrix/matrix-secrets.yaml`. Replace every `CHANGE_ME_BEFORE_DEPLOY` with the values you generated:

```yaml
stringData:
  POSTGRES_USER: synapse
  POSTGRES_PASSWORD: <your-value-1>
  POSTGRES_DB: synapse
  SYNAPSE_MACAROON_SECRET_KEY: <your-value-2>
  SYNAPSE_REGISTRATION_SHARED_SECRET: <your-value-3>
  SYNAPSE_FORM_SECRET: <your-value-4>
```

Do **not** commit this file yet — it still contains plain text.

---

## Step 7 — Populate `apps/matrix/synapse-config.yaml`

Open `apps/matrix/synapse-config.yaml`. This file contains the full Synapse configuration including both secrets and non-secret settings. Edit everything marked with a placeholder:

### 7a — Set `server_name`
```yaml
    server_name: "192.168.1.100"
```
Replace `matrix.example.com` with your value from Step 4.

### 7b — Set `public_baseurl`
```yaml
    public_baseurl: "http://192.168.1.100:30067"
```
Replace `matrix.example.com:30067` with `<NODE_IP>:30067` using your node IP from Step 3.

### 7c — Set the database password
```yaml
    database:
      name: psycopg2
      args:
        user: synapse
        password: <your-value-1>
```
Replace `CHANGE_ME_BEFORE_DEPLOY` with **the same value you used for `POSTGRES_PASSWORD` in Step 6.** These must match or Synapse cannot connect to PostgreSQL.

### 7d — Set `registration_shared_secret`
```yaml
    registration_shared_secret: "<your-value-3>"
```
Replace `CHANGE_ME_BEFORE_DEPLOY` with value 3 from Step 5.

### 7e — Set `macaroon_secret_key` and `form_secret`
```yaml
    macaroon_secret_key: "<your-value-2>"
    form_secret: "<your-value-4>"
```
Replace both `CHANGE_ME_BEFORE_DEPLOY` values with values 2 and 4 from Step 5.

Do **not** commit this file yet.

---

## Step 8 — Verify all placeholders are replaced

Before encrypting, confirm there are no remaining placeholder values in either file:

```bash
grep -n "CHANGE_ME_BEFORE_DEPLOY\|matrix\.example\.com" \
  apps/matrix/matrix-secrets.yaml \
  apps/matrix/synapse-config.yaml
```

This command must return **no output**. Any output means a placeholder was missed — go back and fix it before continuing.

---

## Step 9 — Encrypt both files with SOPS

Use your age public key from Step 1. Replace `age1ql3z7...` with your actual public key:

```bash
AGE_PUBLIC_KEY="age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p"

sops --encrypt \
  --age "$AGE_PUBLIC_KEY" \
  --in-place \
  apps/matrix/matrix-secrets.yaml

sops --encrypt \
  --age "$AGE_PUBLIC_KEY" \
  --in-place \
  apps/matrix/synapse-config.yaml
```

After running these commands, both files are rewritten in place. The `stringData` values and all configuration content are replaced with ciphertext. Verify:

```bash
grep "ENC\[" apps/matrix/matrix-secrets.yaml | head -3
grep "ENC\[" apps/matrix/synapse-config.yaml | head -3
```

You should see multiple lines starting with `ENC[AES256_GCM,...`. This confirms the files are encrypted.

At this point, the files are safe to commit to the public repository.

> **Editing encrypted files in the future:** Use `sops apps/matrix/synapse-config.yaml` (without `--encrypt`). SOPS decrypts the file in memory, opens your `$EDITOR`, and re-encrypts when you save and close. Never manually edit an encrypted file.

---

## Step 10 — Update Element Web configuration

Open `apps/matrix/element.yaml`. Find the `element-config` ConfigMap and update the two placeholder values. This file contains **no secrets** — it is committed in plain text.

**Before:**
```json
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "http://<NODE_IP>:30067",
      "server_name": "matrix.example.com"
    }
  }
}
```

**After:**
```json
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "http://192.168.1.100:30067",
      "server_name": "192.168.1.100"
    }
  }
}
```

- `base_url` must exactly match `public_baseurl` set in `synapse-config.yaml`.
- `server_name` must exactly match `server_name` set in `synapse-config.yaml`.

Confirm no placeholders remain:
```bash
grep -n "NODE_IP\|matrix\.example\.com" apps/matrix/element.yaml
```

This must return no output before you continue.

---

## Step 11 — Commit and push

The encrypted files and updated `element.yaml` are now safe to commit. The secrets in `matrix-secrets.yaml` and `synapse-config.yaml` are ciphertext — decryptable only with the private key stored in your cluster and in your `age.key` file.

```bash
git add apps/matrix/matrix-secrets.yaml \
        apps/matrix/synapse-config.yaml \
        apps/matrix/element.yaml \
        .gitignore

git commit -m "feat(matrix): configure and encrypt Matrix secrets and server identity"
git push
```

> **Before every future commit**, check that no plain-text secrets are accidentally staged:
> ```bash
> git diff --cached apps/matrix/ | grep -i "CHANGE_ME\|password:" | grep -v "ENC\["
> ```
> If any plain-text password or placeholder appears, abort with `git reset HEAD` and re-encrypt.

---

## Step 12 — Watch Flux reconcile

Flux polls the repository every 5 minutes. Trigger an immediate reconcile:

```bash
flux reconcile kustomization apps --with-source
```

Watch reconciliation progress:
```bash
watch flux get kustomizations
```

Expected output once complete:
```
NAME            REVISION        SUSPENDED  READY   MESSAGE
flux-system     main/abc1234    False      True    Applied revision: main/abc1234
infrastructure  main/abc1234    False      True    Applied revision: main/abc1234
apps            main/abc1234    False      True    Applied revision: main/abc1234
```

All three kustomizations must show `READY: True`. The `apps` kustomization uses the `sops-age` Secret you created in Step 2 to decrypt `matrix-secrets.yaml` and `synapse-config.yaml` before applying them.

---

## Step 13 — Verify the pods are running

```bash
kubectl get pods -n matrix
```

Expected (all three `Running`, `READY 1/1`):
```
NAME                               READY   STATUS    RESTARTS   AGE
element-web-xxxxxxxxxx-xxxxx       1/1     Running   0          2m
matrix-postgres-xxxxxxxxxx-xxxxx   1/1     Running   0          3m
synapse-xxxxxxxxxx-xxxxx           1/1     Running   0          2m
```

If any pod is not `Running`, check its logs:
```bash
kubectl logs -n matrix deploy/synapse
kubectl logs -n matrix deploy/matrix-postgres
kubectl logs -n matrix deploy/element-web
```

---

## Step 14 — Confirm Synapse is healthy

```bash
# Port-forward to your workstation
kubectl port-forward -n matrix svc/synapse 8008:8008 &

# Health check (in another terminal)
curl http://localhost:8008/health
# Expected response body: OK

# Matrix API discovery
curl http://localhost:8008/_matrix/client/versions
# Expected: JSON with Matrix spec versions

kill %1  # stop the port-forward
```

You can also check directly on the NodePort from any device on your network:
```bash
curl http://192.168.1.100:30067/health
# Expected: OK
```

---

## Step 15 — Open Element Web

Navigate to `http://192.168.1.100:30080` in your browser.

The Element login screen should appear with the homeserver pre-configured. If you see **"Homeserver not found"**, see the Troubleshooting section below.

---

## Step 16 — Create the first admin user

Open registration is currently enabled, which allows anyone on the network to create an account. Use this window to create your admin account before closing registration in Step 17.

**Option A — via Element Web:**
1. Go to `http://192.168.1.100:30080`
2. Click **Create Account**
3. Register your admin username (e.g. `admin`)

**Option B — via the Synapse admin API (recommended — grants explicit admin rights):**
```bash
kubectl exec -it -n matrix deploy/synapse -- \
  register_new_matrix_user \
  -c /conf/homeserver.yaml \
  -u admin \
  -p '<strong-admin-password>' \
  -a \
  http://localhost:8008
```

The `-a` flag grants server administrator rights. Without it, the account is a regular user.

---

## Step 17 — Disable open registration

Once your initial accounts are created, close registration to prevent unauthorised sign-ups.

Edit `synapse-config.yaml` using SOPS (so the file stays encrypted):
```bash
sops apps/matrix/synapse-config.yaml
```

Your editor opens with the decrypted content. Find these two lines and change them:
```yaml
    enable_registration: false
    enable_registration_without_verification: false
```

Save and close the editor. SOPS re-encrypts the file automatically.

Commit and push:
```bash
git add apps/matrix/synapse-config.yaml
git commit -m "feat(matrix): disable open registration"
git push
```

Flux will reconcile and restart Synapse. Monitor:
```bash
kubectl rollout status -n matrix deploy/synapse
```

---

## Step 18 — Final validation

```bash
# All Matrix pods running
kubectl get pods -n matrix

# Synapse health
curl http://192.168.1.100:30067/health
# Expected: OK

# Registration is closed (expect HTTP 403 or M_FORBIDDEN)
curl -s http://192.168.1.100:30067/_matrix/client/v3/register \
  -X POST -H "Content-Type: application/json" -d '{"kind":"guest"}' \
  | python3 -m json.tool | grep -i "errcode"
# Expected: "errcode": "M_FORBIDDEN" or similar

# Flux reports all kustomizations healthy
flux get kustomizations
```

---

## Reference: all required changes at a glance

| File | What to change | Notes |
|---|---|---|
| `apps/matrix/matrix-secrets.yaml` | All 4 `CHANGE_ME_BEFORE_DEPLOY` values | Replace, then encrypt with SOPS |
| `apps/matrix/synapse-config.yaml` | `server_name`, `public_baseurl`, database `password`, `registration_shared_secret`, `macaroon_secret_key`, `form_secret` | Replace all, then encrypt with SOPS |
| `apps/matrix/element.yaml` | `base_url`, `server_name` in `config.json` | Plain text — no encryption needed |

The `sops-age` Kubernetes Secret (Step 2) is applied out-of-band and never committed to Git.

---

## Cluster recovery / rebuilding from scratch

If the cluster is wiped and you need to restore the Matrix deployment:

1. Install K3s and bootstrap Flux as documented in `README.md`.
2. Retrieve your age private key from your secure backup (password manager, encrypted drive).
3. Re-create the `sops-age` Secret in the new cluster:
   ```bash
   kubectl create secret generic sops-age \
     --namespace=flux-system \
     --from-file=age.agekey=age.key
   ```
4. Flux reconciles automatically. It decrypts the SOPS-encrypted files using the key you just provided and re-creates the Matrix stack.

No other manual steps are needed. The encrypted Git state is the source of truth.

> **PostgreSQL data is stored in a PersistentVolume on the node's USB storage.** If the storage is intact, data survives a cluster wipe and reinstall as long as the PVC is rebound. If storage is lost, the database must be restored from a backup (database backups are outside the scope of this guide).

---

## Making future configuration changes

### Changing non-secret Synapse settings (e.g. disabling federation)

Edit `synapse-config.yaml` via SOPS:
```bash
sops apps/matrix/synapse-config.yaml
# Make your changes in the editor, save, close.
git add apps/matrix/synapse-config.yaml
git commit -m "chore(matrix): <describe change>"
git push
```

### Rotating secrets

If you need to rotate any secret:

1. Open `matrix-secrets.yaml` for editing:
   ```bash
   sops apps/matrix/matrix-secrets.yaml
   ```
2. Update the relevant value, save, and close. SOPS re-encrypts automatically.
3. If you rotated `POSTGRES_PASSWORD`, also open `synapse-config.yaml` and update `database.args.password` to match:
   ```bash
   sops apps/matrix/synapse-config.yaml
   ```
4. Commit and push both files.
5. The PostgreSQL user password is NOT automatically updated in the database. After Flux reconciles (which will start failing because Synapse can't connect), reset the password in the database:
   ```bash
   kubectl exec -it -n matrix deploy/matrix-postgres -- \
     psql -U synapse -c "ALTER USER synapse PASSWORD '<new-password>';"
   ```

---

## Troubleshooting

### Flux `apps` kustomization failing to decrypt

```bash
kubectl describe kustomization -n flux-system apps | grep -A 20 "Status:"
flux logs --kind=Kustomization --name=apps --namespace=flux-system
```

Common causes:
- **`sops-age` Secret is missing**: run `kubectl get secret sops-age -n flux-system`. If absent, re-create it (Step 2).
- **Wrong age key**: the `sops-age` Secret holds a different private key than what was used to encrypt. Re-encrypt with the correct key or restore the correct `age.key`.
- **File not encrypted**: if `matrix-secrets.yaml` or `synapse-config.yaml` was committed in plain text, Flux may try to apply it without decryption errors, but credentials end up exposed. Check:
  ```bash
  git show HEAD:apps/matrix/matrix-secrets.yaml | grep "ENC\["
  # Must show encrypted values, not CHANGE_ME_BEFORE_DEPLOY or plain passwords
  ```

### Synapse pod is in `CrashLoopBackOff`

```bash
kubectl logs -n matrix deploy/synapse --previous
```

Common causes:
- **Database connection refused** — the password in `synapse-config.yaml` does not match `POSTGRES_PASSWORD`. Open both files with `sops` and verify they are identical. Reconcile after fixing.
- **YAML syntax error** — an error was introduced while editing `synapse-config.yaml`. The homeserver.yaml is a YAML file embedded as a string inside YAML; indentation errors are common. Check for misaligned lines.
- **PostgreSQL not ready** — check: `kubectl logs -n matrix deploy/matrix-postgres`

### PostgreSQL pod is in `CrashLoopBackOff`

```bash
kubectl logs -n matrix deploy/matrix-postgres
```

If a previous run left the data directory with a different password, delete the PVC to reset:
```bash
kubectl delete pvc -n matrix matrix-postgres-data
flux reconcile kustomization apps --with-source
```

> **Warning:** This destroys all database data. Only do this before any real accounts or rooms exist.

### Element Web shows "Homeserver not found"

1. Confirm Synapse is reachable: `curl http://192.168.1.100:30067/health`
2. Open the browser developer tools (F12 → Console) and look for the exact network error.
3. Confirm `base_url` in `element.yaml` exactly matches `public_baseurl` in `synapse-config.yaml`:
   ```bash
   # Check element.yaml (plain text, grep directly)
   grep "base_url" apps/matrix/element.yaml

   # Check synapse-config.yaml (encrypted, use sops to read)
   sops --decrypt apps/matrix/synapse-config.yaml | grep "public_baseurl"
   ```

### Checking decrypted values without editing

To inspect the current decrypted content of a SOPS-encrypted file:
```bash
sops --decrypt apps/matrix/matrix-secrets.yaml
sops --decrypt apps/matrix/synapse-config.yaml
```

This prints the plain-text content to stdout without saving it anywhere.

### Verifying no plain-text secrets are in Git history

```bash
# Check current HEAD
git show HEAD:apps/matrix/matrix-secrets.yaml | grep -v "ENC\[" | grep -i "password\|secret\|key"

# Check last 10 commits
git log --oneline -10 | awk '{print $1}' | while read sha; do
  result=$(git show "$sha":apps/matrix/matrix-secrets.yaml 2>/dev/null | grep -v "ENC\[" | grep -i "password\|secret\|key")
  [ -n "$result" ] && echo "⚠️  Plain-text secret found in commit $sha"
done
```

If a plain-text secret was ever committed, treat it as compromised: rotate the value, re-encrypt, and consider the repository history permanently tainted (even after a `git push --force`, the history may be cached elsewhere).

---

## Known limitations

- **No TLS**: served over HTTP. Add an ingress controller with cert-manager for HTTPS. Note: changing to HTTPS requires updating `server_name`, `public_baseurl`, and `element.yaml` — see AGENTS.md before adding ingress.
- **No TURN/VoIP**: voice and video calls across NAT require a TURN server (e.g. coturn), which is not configured.
- **Single replica**: no high availability — appropriate for edge/SBC.
- **No SSO/OIDC**: password authentication only.
- **Federation enabled**: Synapse federates with matrix.org and other public servers by default. Add `federation_domain_whitelist` to `synapse-config.yaml` (via `sops`) to restrict this.

