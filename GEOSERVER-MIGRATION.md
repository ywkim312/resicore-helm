# GeoServer Data Migration (incore-prod to microk8s)

Two approaches available:

## Approach A: Copy via local machine (migrate-geoserver-copy.sh)

Recommended when you have kubectl access to both clusters. Copies full data_dir, filters layer dirs to ergo/incore only, preserves password, and fixes URLs.

**Prereqs:**
- `geoserver-dataset-ids.txt` (from `migrate-geoserver-dataset-ids.js` on prod)
- GeoServer deployed on microk8s first (so `security/` exists with password from values)

```bash
cd tmp
bash ../migrate-geoserver-copy.sh
```

**What it does:**
- Copy full data_dir from prod
- Remove layer dirs not in ergo/incore
- Exclude `security/` so password from `values-geoserver-resicore-ai.yaml` is preserved
- Replace `tools.in-core.org` / `dev.in-core.org` with `dev.resicore.ai` in XML/properties
- Tar and deploy to microk8s

Override target host: `TARGET_HOST=myhost.example.com bash ../migrate-geoserver-copy.sh`

---

## Approach B: Direct pod-to-pod rsync

Direct pod-to-pod rsync between clusters. No local machine, no NFS.

**Requirement:** incore-prod pods must be able to reach microk8s LoadBalancer IP (network connectivity between clusters).

### Overview

1. **Receiver** (microk8s): rsync daemon pod + LoadBalancer service. Receives data into GeoServer PVC.
2. **Sender** (incore-prod): Job that reads from prod GeoServer PVC and pushes to receiver via rsync.

### Dry Run (Recommended First)

Run a dry run to verify connectivity and see what would be transferred:

1. Deploy receiver (steps 1-4 below)
2. Edit `geoserver-migration-sender-dryrun.yaml` - replace `REPLACE_WITH_RECEIVER_IP`
3. `kubectl apply -f geoserver-migration-sender-dryrun.yaml --context incore-prod`
4. `kubectl logs -f job/geoserver-migration-sender-dryrun -n incore --context incore-prod`
5. Verify output shows file list (no actual transfer). Delete job: `kubectl delete job geoserver-migration-sender-dryrun -n incore --context incore-prod`

### Step-by-Step

### 1. Scale down GeoServer in microk8s

```bash
kubectl scale deployment geoserver -n incore --replicas=0 --context microk8s
```

### 2. Delete any previous migration Job (if exists)

```bash
kubectl delete job geoserver-migration -n incore --context microk8s --ignore-not-found
```

### 3. Deploy receiver in microk8s

```bash
kubectl apply -f geoserver-migration-receiver.yaml --context microk8s
```

### 4. Wait for receiver and get its external IP

```bash
kubectl get svc geoserver-migration-receiver -n incore --context microk8s -w
```

Wait until EXTERNAL-IP is assigned (e.g. 172.93.109.xxx). Note this IP.

### 5. Update sender with receiver IP

Edit `geoserver-migration-sender.yaml` and replace `REPLACE_WITH_RECEIVER_IP` with the actual IP.

### 6. Run sender in incore-prod

```bash
kubectl apply -f geoserver-migration-sender.yaml --context incore-prod
```

### 7. Wait for sender Job to complete

```bash
kubectl wait --for=condition=complete job/geoserver-migration-sender -n incore --context incore-prod --timeout=2h
kubectl logs job/geoserver-migration-sender -n incore --context incore-prod
```

### 8. Clean up receiver and scale GeoServer back up

```bash
kubectl delete -f geoserver-migration-receiver.yaml --context microk8s
kubectl scale deployment geoserver -n incore --replicas=1 --context microk8s
```

### 9. Delete sender Job (optional)

```bash
kubectl delete job geoserver-migration-sender -n incore --context incore-prod
```

### Troubleshooting

- **Sender cannot connect:** Run the dry-run Job first. If it fails to connect, verify prod pods can reach the receiver LoadBalancer IP (firewall, network routing).
- **Receiver PVC in use:** Ensure GeoServer is scaled to 0 before deploying receiver.
- **Prod PVC name:** If prod uses a different PVC name, update `claimName` in the sender YAML.
