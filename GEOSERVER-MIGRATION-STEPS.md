# GeoServer Migration – Step-by-Step Guide (with confirmation)

Use this guide to migrate GeoServer data from incore-prod to microk8s (dev.resicore.ai).

---

## Files to Push to Repo (for pulling on VM)

Push these files so you can `git pull` them on your VM:

| File | Purpose |
|------|---------|
| `migrate-geoserver-copy.sh` | Main migration script |
| `migrate-geoserver-dataset-ids.js` | Generates dataset ID list (run on prod) |
| `GEOSERVER-MIGRATION.md` | Documentation (optional) |
| `GEOSERVER-MIGRATION-STEPS.md` | This guide (optional) |

**Note:** `geoserver-dataset-ids.txt` is generated in Step 2 and is not in the repo. You will create it on prod and copy it to your VM.

---

## Prerequisites (verify before starting)

- [ ] `kubectl` configured with contexts: `incore-prod` and `microk8s`
- [ ] GeoServer deployed on microk8s (at least once) so `security/` exists with password from values
- [ ] MongoDB root password for incore-prod (for Step 2)

---

## Step 1: Push and pull migration files

**On your dev machine (where you have the repo):**

```bash
cd c:\Workspace-ywkim\resicore-helm
git add migrate-geoserver-copy.sh migrate-geoserver-dataset-ids.js GEOSERVER-MIGRATION.md GEOSERVER-MIGRATION-STEPS.md
git status   # verify
git commit -m "Add GeoServer migration scripts (full data_dir + filter layers, preserve password, fix URLs)"
git push
```

**On your VM:**

```bash
cd /path/to/resicore-helm   # or wherever your repo is
git pull
```

**Confirm:** `ls migrate-geoserver-copy.sh migrate-geoserver-dataset-ids.js` shows both files.

---

## Step 2: Generate geoserver-dataset-ids.txt on prod

**Where:** Run from any machine that has `kubectl` access to incore-prod.

**Replace `PASSWORD`** with the actual MongoDB root password for incore-prod.

```bash
cd /path/to/resicore-helm
mkdir -p tmp
cd tmp
cat ../migrate-geoserver-dataset-ids.js | kubectl exec -i incore-mongodb-0 -n incore --context incore-prod -- mongo "mongodb://root:PASSWORD@localhost:27017/admin" --quiet > geoserver-dataset-ids.txt
```

**Confirm:** `wc -l geoserver-dataset-ids.txt` shows a non-zero count. `head -5 geoserver-dataset-ids.txt` shows 24-char hex IDs.

**If you run this from your dev machine (not VM):** Copy `geoserver-dataset-ids.txt` to your VM’s `tmp/` directory (e.g. via SCP, shared folder, or push to a private branch).

---

## Step 3: Ensure geoserver-dataset-ids.txt is on VM

**On your VM:**

```bash
cd /path/to/resicore-helm/tmp
ls -la geoserver-dataset-ids.txt
```

**Confirm:** File exists and has content. If not, copy it from where you generated it in Step 2.

---

## Step 4: Verify kubectl access to both clusters

**On your VM:**

```bash
kubectl get pods -n incore --context incore-prod -l app.kubernetes.io/name=geoserver
kubectl get pods -n incore --context microk8s -l app.kubernetes.io/name=geoserver
```

**Confirm:** Both commands return at least one GeoServer pod.

---

## Step 5: (Optional) Scale down GeoServer on microk8s

Reduces risk of file locks during extract. You can skip if the pod is idle.

```bash
kubectl scale deployment geoserver -n incore --replicas=0 --context microk8s
```

**Confirm:** `kubectl get pods -n incore --context microk8s -l app.kubernetes.io/name=geoserver` shows 0 pods (or you chose to skip).

---

## Step 6: Run the migration script

**On your VM:**

```bash
cd /path/to/resicore-helm/tmp
bash ../migrate-geoserver-copy.sh
```

The script will:

1. Copy full data_dir from prod
2. Remove layer dirs not in ergo/incore
3. Exclude `security/` (preserve password)
4. Fix URLs in XML/properties
5. Tar and deploy to microk8s

**Confirm:** Script completes without errors. Check the printed summary (layers copied, removed, files updated).

---

## Step 7: Scale GeoServer back up (if you scaled down in Step 5)

```bash
kubectl scale deployment geoserver -n incore --replicas=1 --context microk8s
```

**Confirm:** `kubectl get pods -n incore --context microk8s -l app.kubernetes.io/name=geoserver` shows 1 Running pod.

---

## Step 8: Restart GeoServer (recommended)

Ensures it reloads the migrated config and data.

```bash
kubectl rollout restart deployment/geoserver -n incore --context microk8s
kubectl rollout status deployment/geoserver -n incore --context microk8s
```

**Confirm:** Pod restarts and becomes Ready.

---

## Step 9: Verify

1. **Login:** https://dev.resicore.ai/geoserver/ — admin / password from `values-geoserver-resicore-ai.yaml`
2. **Layers:** Check that ergo/incore layers appear and can be previewed
3. **Data viewer:** Open a dataset in the data viewer and confirm the map loads

---

## Troubleshooting

| Issue | Action |
|------|--------|
| `geoserver-dataset-ids.txt` missing | Re-run Step 2, ensure file is in `tmp/` |
| No prod GeoServer pod | Check prod cluster; ensure GeoServer is deployed |
| No microk8s GeoServer pod | Deploy GeoServer first: `helm upgrade --install geoserver ncsa/geoserver -n incore -f values-geoserver-resicore-ai.yaml --context microk8s` |
| Wrong password after migration | Ensure you scaled down before extract, or that `security/` was excluded (Phase 2b in script) |
| Different target host | `TARGET_HOST=myhost.example.com bash ../migrate-geoserver-copy.sh` |
