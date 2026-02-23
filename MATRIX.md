# Matrix Deployment Guide

This guide walks you through making the Matrix stack — **Synapse** (homeserver), **Element Web** (client), and **PostgreSQL** (database) — fully operational on your K3s cluster.

The manifests are already present in `apps/matrix/`. Before they can work, you must supply real values for several placeholder fields. This guide tells you exactly what to change, where, and why, then shows you how to push the change so FluxCD (the GitOps controller) applies it automatically.

---

## How FluxCD works (brief summary)

FluxCD watches this Git repository. When you push a commit, FluxCD notices the change and applies the updated manifests to the cluster — no `kubectl apply` required. That means **all configuration changes go through Git**.

---

## Prerequisites

- `kubectl` access to the K3s cluster (run `kubectl get nodes` to verify)
- Write access to this Git repository
- `git` installed on your workstation
- The cluster must already have Flux bootstrapped and reconciling (run `flux get kustomizations` to check)

---

## Step 1 — Find your K3s node IP address

All placeholder references to `<NODE_IP>` must be replaced with the actual IP address of your K3s node. This is the IP address that clients (browsers, Matrix apps) will use to reach Synapse and Element.

```bash
kubectl get nodes -o wide
```

Look at the `INTERNAL-IP` column. For a single-node cluster on a Raspberry Pi connected to your home network this will be something like `192.168.1.100`.

> **Why this matters:** Synapse embeds its own public URL in federation responses and client discovery documents. If the URL is wrong, Matrix clients cannot connect and federation with other servers will fail.

---

## Step 2 — Decide on your `server_name`

`server_name` is the **Matrix identity domain** — it is the part after the colon in Matrix IDs such as `@alice:example.com`. This value **cannot be changed after the first user is created** without wiping the database and starting over.

Choose carefully:

| Scenario | Recommended `server_name` |
|---|---|
| Personal homeserver, no public DNS | Use the node IP, e.g. `192.168.1.100` |
| You own a domain and will add DNS later | Use your domain, e.g. `matrix.yourdomain.com` |
| Local testing only | `localhost` (not reachable by others) |

For a home lab, using the node IP as the server name is the simplest option and requires no DNS configuration. The examples throughout this document use `192.168.1.100` — replace it with your actual IP.

---

## Step 3 — Generate secrets

The Matrix stack requires four independent random secrets. Generate them now and keep the output somewhere safe — you will paste them into the manifests in the next steps.

```bash
# Run each line separately; save every output value
python3 -c "import secrets; print(secrets.token_hex(32))"   # 1. POSTGRES_PASSWORD
python3 -c "import secrets; print(secrets.token_hex(32))"   # 2. MACAROON_SECRET_KEY
python3 -c "import secrets; print(secrets.token_hex(32))"   # 3. REGISTRATION_SHARED_SECRET
python3 -c "import secrets; print(secrets.token_hex(32))"   # 4. FORM_SECRET
```

Each command produces a different 64-character hex string, for example:

```
a3f8c2e1d4b7a0f9e6c3d1b8a5f2e9c6d3b0a7f4e1c8d5b2a9f6e3c0d7b4a1f8
```

Label your four values clearly. You will need all four in Steps 4 and 5.

> **Security note:** These secrets protect your Matrix server against token forgery and database access. Never commit them to a public repository in plain text. For a private repository this is acceptable for a home lab; for any public or shared repository use SOPS encryption (see [Production Hardening](#production-hardening) below).

---

## Step 4 — Edit `apps/matrix/postgres.yaml`

Open `apps/matrix/postgres.yaml` in your editor. Find the `Secret` resource named `matrix-secrets` (near the top of the file).

**Before:**
```yaml
stringData:
  POSTGRES_USER: synapse
  POSTGRES_PASSWORD: CHANGE_ME_BEFORE_DEPLOY
  POSTGRES_DB: synapse
  SYNAPSE_MACAROON_SECRET_KEY: CHANGE_ME_BEFORE_DEPLOY
  SYNAPSE_REGISTRATION_SHARED_SECRET: CHANGE_ME_BEFORE_DEPLOY
  SYNAPSE_FORM_SECRET: CHANGE_ME_BEFORE_DEPLOY
```

**After** (replace with your generated values from Step 3):
```yaml
stringData:
  POSTGRES_USER: synapse
  POSTGRES_PASSWORD: a3f8c2e1d4b7a0f9e6c3d1b8a5f2e9c6d3b0a7f4e1c8d5b2a9f6e3c0d7b4a1f8
  POSTGRES_DB: synapse
  SYNAPSE_MACAROON_SECRET_KEY: <your-value-2>
  SYNAPSE_REGISTRATION_SHARED_SECRET: <your-value-3>
  SYNAPSE_FORM_SECRET: <your-value-4>
```

> **Why this file holds all four secrets:** PostgreSQL needs `POSTGRES_PASSWORD` at startup to create the database user. The three Synapse secrets (`MACAROON_SECRET_KEY`, `REGISTRATION_SHARED_SECRET`, `FORM_SECRET`) are stored here in the same Kubernetes Secret so that a future SOPS encryption step only needs to encrypt one file.

---

## Step 5 — Edit `apps/matrix/synapse.yaml`

Open `apps/matrix/synapse.yaml`. This file contains the `synapse-config` ConfigMap with Synapse's `homeserver.yaml` configuration embedded inside it.

You need to make **five replacements** in this file.

### 5a — Set `server_name`

Find the line:
```yaml
    server_name: "matrix.example.com"
```

Replace with your chosen server name from Step 2:
```yaml
    server_name: "192.168.1.100"
```

### 5b — Set `public_baseurl`

Find the line:
```yaml
    public_baseurl: "http://matrix.example.com:30067"
```

Replace with the URL that browsers and Matrix apps will use to reach your Synapse:
```yaml
    public_baseurl: "http://192.168.1.100:30067"
```

Port `30067` is the NodePort already defined in the Service — do not change it unless you also change the `nodePort` value in the Service spec.

### 5c — Set the database password

Find the database block:
```yaml
    database:
      name: psycopg2
      args:
        user: synapse
        # ⚠️  Must match POSTGRES_PASSWORD in matrix-secrets Secret
        password: CHANGE_ME_BEFORE_DEPLOY
```

Replace `CHANGE_ME_BEFORE_DEPLOY` with **the same value you used for `POSTGRES_PASSWORD` in Step 4**. These two values must be identical or Synapse will fail to connect to PostgreSQL.

```yaml
        password: a3f8c2e1d4b7a0f9e6c3d1b8a5f2e9c6d3b0a7f4e1c8d5b2a9f6e3c0d7b4a1f8
```

### 5d — Set `registration_shared_secret`

Find:
```yaml
    registration_shared_secret: "CHANGE_ME_BEFORE_DEPLOY"
```

Replace with your value 3 from Step 3 (must match `SYNAPSE_REGISTRATION_SHARED_SECRET` in Step 4):
```yaml
    registration_shared_secret: "<your-value-3>"
```

### 5e — Set `macaroon_secret_key` and `form_secret`

Find:
```yaml
    macaroon_secret_key: "CHANGE_ME_BEFORE_DEPLOY"
```
Replace with your value 2 from Step 3 (must match `SYNAPSE_MACAROON_SECRET_KEY`).

Find:
```yaml
    form_secret: "CHANGE_ME_BEFORE_DEPLOY"
```
Replace with your value 4 from Step 3 (must match `SYNAPSE_FORM_SECRET`).

> **Why the ConfigMap contains secrets:** Synapse reads its configuration from `homeserver.yaml` as a file mounted from the ConfigMap. Unlike environment variables, Kubernetes cannot inject individual Secret keys into a YAML file — so the password and cryptographic keys appear here. This is a known limitation of how Synapse is configured. The values in this ConfigMap must exactly match the values in the `matrix-secrets` Secret in `postgres.yaml`.

---

## Step 6 — Edit `apps/matrix/element.yaml`

Open `apps/matrix/element.yaml`. Find the `element-config` ConfigMap containing `config.json`.

**Before:**
```json
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "http://<NODE_IP>:30067",
      "server_name": "matrix.example.com"
    }
  },
  ...
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
  },
  ...
}
```

- `base_url` must exactly match `public_baseurl` set in `synapse.yaml` (Step 5b).
- `server_name` must exactly match `server_name` set in `synapse.yaml` (Step 5a).

> **Why Element needs these values:** Element is a static web app running in the browser. It needs to know the URL to reach Synapse (`base_url`) and the Matrix identity domain (`server_name`) before it can display the login screen. If these are wrong, you will see "Homeserver not found" errors.

---

## Step 7 — Verify your changes before committing

Before pushing, do a quick sanity check to confirm all placeholders are gone:

```bash
# Should return no output (no remaining placeholders)
grep -r "CHANGE_ME_BEFORE_DEPLOY" apps/matrix/
grep -r "<NODE_IP>" apps/matrix/
grep -r "matrix\.example\.com" apps/matrix/
```

If any line is returned, go back and fix it before continuing.

Also confirm the password value matches across both files:

```bash
# Extract password from postgres.yaml (should be identical in both outputs)
grep "POSTGRES_PASSWORD:" apps/matrix/postgres.yaml
grep "password:" apps/matrix/synapse.yaml | head -1
```

---

## Step 8 — Commit and push

FluxCD applies changes from Git. You must commit and push for the cluster to receive the updated manifests.

```bash
git add apps/matrix/postgres.yaml apps/matrix/synapse.yaml apps/matrix/element.yaml
git commit -m "feat(matrix): configure secrets and server identity"
git push
```

> **What happens next:** FluxCD polls the repository every 5 minutes (or sooner if you trigger it manually). It will detect the new commit, build the manifests, and apply them to the cluster. PostgreSQL will start first; Synapse has an init container that waits for PostgreSQL to be ready before starting; Element Web starts last.

---

## Step 9 — Watch Flux reconcile

On your cluster (or via `kubectl` from your workstation):

```bash
# Watch Flux apply the change (refresh every 5 seconds)
watch flux get kustomizations

# Or trigger reconciliation immediately without waiting for the poll interval
flux reconcile kustomization apps --with-source
```

Expected output once reconciled:
```
NAME            REVISION        SUSPENDED  READY   MESSAGE
flux-system     main/abc1234    False      True    Applied revision: main/abc1234
infrastructure  main/abc1234    False      True    Applied revision: main/abc1234
apps            main/abc1234    False      True    Applied revision: main/abc1234
```

All three kustomizations should show `READY: True`.

---

## Step 10 — Verify the pods are running

```bash
kubectl get pods -n matrix
```

Expected output (all three pods `Running`, `READY 1/1`):
```
NAME                              READY   STATUS    RESTARTS   AGE
element-web-xxxxxxxxxx-xxxxx      1/1     Running   0          2m
matrix-postgres-xxxxxxxxxx-xxxxx  1/1     Running   0          3m
synapse-xxxxxxxxxx-xxxxx          1/1     Running   0          2m
```

If a pod is not `Running`, check its logs:
```bash
kubectl logs -n matrix deploy/synapse
kubectl logs -n matrix deploy/matrix-postgres
kubectl logs -n matrix deploy/element-web
```

---

## Step 11 — Confirm Synapse is healthy

```bash
# Port-forward Synapse to your workstation
kubectl port-forward -n matrix svc/synapse 8008:8008

# In a second terminal, check the health endpoint
curl http://localhost:8008/health
# Expected response: OK

# Confirm the Matrix API is responding
curl http://localhost:8008/_matrix/client/versions
# Expected: JSON object listing Matrix spec versions
```

You can also check Synapse directly on the NodePort from any machine on your network:

```bash
curl http://192.168.1.100:30067/health
# Expected: OK
```

---

## Step 12 — Open Element Web

Navigate to `http://192.168.1.100:30080` in your browser.

You should see the Element Web login screen. The homeserver should already be pre-filled to your server name from the config.

If you see a **"Homeserver not found"** error, confirm:
- `base_url` in `element.yaml` matches `public_baseurl` in `synapse.yaml`
- The Synapse NodePort (30067) is reachable: `curl http://192.168.1.100:30067/health`

---

## Step 13 — Create the first admin user

Registration is currently open (`enable_registration: true`) which allows anyone on the network to create an account. Use this window to create your admin account.

**Option A — via Element Web (simplest)**

1. Open `http://192.168.1.100:30080`
2. Click **Create Account**
3. Create your admin account (e.g. username: `admin`)

**Option B — via the Synapse admin API (more reliable)**

```bash
kubectl exec -it -n matrix deploy/synapse -- \
  register_new_matrix_user \
  -c /conf/homeserver.yaml \
  -u admin \
  -p '<strong-admin-password>' \
  -a \
  http://localhost:8008
```

The `-a` flag grants admin rights. Without it the account is a regular user.

> **Important:** Do this before disabling open registration in Step 14.

---

## Step 14 — Disable open registration

Once your admin account (and any other initial accounts) are created, disable open registration so that random users cannot sign up.

Edit `apps/matrix/synapse.yaml`. Find these two lines in the ConfigMap:

```yaml
    enable_registration: true
    enable_registration_without_verification: true
```

Change them to:
```yaml
    enable_registration: false
    enable_registration_without_verification: false
```

Commit and push:
```bash
git add apps/matrix/synapse.yaml
git commit -m "feat(matrix): disable open registration"
git push
```

Flux will apply the change and restart Synapse automatically. Verify with:
```bash
kubectl rollout status -n matrix deploy/synapse
```

---

## Step 15 — Final end-to-end check

```bash
# All Matrix pods healthy
kubectl get pods -n matrix

# Synapse health endpoint
curl http://192.168.1.100:30067/health

# Registration is disabled (should return HTTP 403 or error JSON, not a registration form)
curl -s http://192.168.1.100:30067/_matrix/client/v3/register | grep -i "forbidden\|not allowed\|M_FORBIDDEN"

# Flux shows all kustomizations as READY
flux get kustomizations
```

---

## Reference: Summary of all changes required

| File | Field | What to set |
|---|---|---|
| `apps/matrix/postgres.yaml` | `POSTGRES_PASSWORD` | Generated secret (value 1 from Step 3) |
| `apps/matrix/postgres.yaml` | `SYNAPSE_MACAROON_SECRET_KEY` | Generated secret (value 2) |
| `apps/matrix/postgres.yaml` | `SYNAPSE_REGISTRATION_SHARED_SECRET` | Generated secret (value 3) |
| `apps/matrix/postgres.yaml` | `SYNAPSE_FORM_SECRET` | Generated secret (value 4) |
| `apps/matrix/synapse.yaml` | `server_name` | Your Matrix identity domain (cannot change later) |
| `apps/matrix/synapse.yaml` | `public_baseurl` | `http://<NODE_IP>:30067` |
| `apps/matrix/synapse.yaml` | `database.args.password` | Same as `POSTGRES_PASSWORD` above |
| `apps/matrix/synapse.yaml` | `registration_shared_secret` | Same as `SYNAPSE_REGISTRATION_SHARED_SECRET` above |
| `apps/matrix/synapse.yaml` | `macaroon_secret_key` | Same as `SYNAPSE_MACAROON_SECRET_KEY` above |
| `apps/matrix/synapse.yaml` | `form_secret` | Same as `SYNAPSE_FORM_SECRET` above |
| `apps/matrix/element.yaml` | `base_url` | Same as `public_baseurl` above |
| `apps/matrix/element.yaml` | `server_name` | Same as `server_name` above |

---

## Production hardening

The steps above are sufficient for a private home lab. For a more hardened setup, consider the following improvements. None of them are required to get Matrix working, but they are worth addressing before exposing the service publicly.

### Encrypt secrets with SOPS + age (recommended)

Storing plain-text secrets in Git is acceptable for a private repository but is a bad practice for any repo that might become public. SOPS encrypts secret values in place so the ciphertext is committed to Git and Flux decrypts it at apply time.

1. Install `age` and `sops` on your workstation.
2. Generate an age keypair:
   ```bash
   age-keygen -o age.key
   # Note the public key printed (starts with "age1...")
   ```
3. Create a Kubernetes Secret that holds the age private key so Flux can decrypt:
   ```bash
   cat age.key | kubectl create secret generic sops-age \
     --namespace=flux-system \
     --from-file=age.agekey=/dev/stdin
   ```
4. Patch the `kustomize-controller` to use the age key (see [Flux SOPS guide](https://fluxcd.io/flux/guides/mozilla-sops/)).
5. Create a `.sops.yaml` rule file in the repo root:
   ```yaml
   creation_rules:
     - path_regex: apps/matrix/.*\.yaml$
       age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```
6. Encrypt `apps/matrix/postgres.yaml`:
   ```bash
   sops --encrypt --in-place apps/matrix/postgres.yaml
   ```
7. The file now contains encrypted ciphertext for all secret values. Commit it normally.

From this point forward, edit secret values with `sops apps/matrix/postgres.yaml` (it decrypts in memory, opens your editor, then re-encrypts on save).

### Add TLS with cert-manager

The current setup serves everything over plain HTTP on NodePorts. For any exposure beyond your local LAN, add TLS:

1. Deploy cert-manager (add to `infrastructure/`) using the [cert-manager Helm chart](https://cert-manager.io/docs/installation/helm/).
2. Add an `Ingress` resource to `apps/matrix/` with a `cert-manager.io/cluster-issuer` annotation.
3. Point a real domain (`matrix.yourdomain.com`) to your node's IP via DNS.
4. Update `server_name` and `public_baseurl` in `synapse.yaml` to use `https://matrix.yourdomain.com`.
5. Update `base_url` in `element.yaml` to match.

> **Important:** Changing `server_name` after users and rooms have been created is not supported. Set the final domain name before creating any accounts.

### Restrict federation

By default, Synapse federates with any Matrix server including `matrix.org`. To limit this to specific servers (or disable federation entirely):

Edit `apps/matrix/synapse.yaml` and add inside `homeserver.yaml`:
```yaml
    # Allow federation only with specific servers
    federation_domain_whitelist:
      - matrix.org
      - your-trusted-server.example.com

    # OR disable federation entirely
    # federation_sender_instances: []
    # federation_rcv_ignore_list:
    #   - "*"
```

### Add TURN/STUN for voice and video calls

Voice and video calls between clients behind NAT require a TURN server (e.g. coturn). Without it, calls will fail in most home network configurations. This is an explicit known limitation of the current deployment — add coturn to `infrastructure/` if you need calling support.

---

## Troubleshooting

### Synapse pod is `CrashLoopBackOff`

```bash
kubectl logs -n matrix deploy/synapse --previous
```

Common causes:
- **Database connection refused**: the password in the ConfigMap does not match `POSTGRES_PASSWORD` in the Secret. Re-check Step 5c.
- **Invalid configuration**: a YAML syntax error in the embedded `homeserver.yaml`. Validate the file locally with `kustomize build apps/matrix/`.
- **PostgreSQL not ready**: the init container should handle this, but if Postgres itself is crashing, check `kubectl logs -n matrix deploy/matrix-postgres`.

### PostgreSQL pod is `CrashLoopBackOff`

```bash
kubectl logs -n matrix deploy/matrix-postgres
```

Common cause: a previous run created the data directory with a different password. Delete the PVC and let Kubernetes recreate it:

```bash
kubectl delete pvc -n matrix matrix-postgres-data
# Flux will recreate it on next reconcile
flux reconcile kustomization apps --with-source
```

> **Warning:** This deletes all database data. Only do this before any real data exists.

### Element Web shows "Homeserver not found"

1. Confirm Synapse is running: `curl http://192.168.1.100:30067/health`
2. Confirm `base_url` in `element.yaml` exactly matches `public_baseurl` in `synapse.yaml`
3. Check the browser console (F12 → Console) for the exact error

### Flux not applying the changes

```bash
# Check for reconciliation errors
flux get kustomizations
kubectl describe kustomization -n flux-system apps

# Force a fresh reconcile
flux reconcile kustomization apps --with-source

# Check for YAML errors in your edits
kustomize build apps/matrix/
```

### Verify all placeholders are gone

```bash
grep -rn "CHANGE_ME_BEFORE_DEPLOY\|<NODE_IP>\|matrix\.example\.com" apps/matrix/
```

This command should return no output. Any output means there is still a placeholder that needs replacing.
