# IN-CORE Deployment on MicroK8s (resicore.ai)

Deployment guide for IN-CORE on the resicore.ai MicroK8s cluster (domain: `dev.resicore.ai`). This repository was forked from [incore-helm](https://github.com/IN-CORE/incore-helm).

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Prerequisites](#prerequisites)
3. [Deployment Steps](#deployment-steps)
4. [GeoServer](#geoserver)
5. [incore-auth (Access Control)](#incore-auth-access-control)
6. [Database Migrations](#database-migrations)
7. [Troubleshooting](#troubleshooting)

---

## Quick Reference

### Cluster Information

| Item | Value |
|------|-------|
| Cluster | MicroK8s (3 nodes: coruscant, hoth, naboo) |
| Kubernetes | v1.33.7 |
| Control Plane | `https://104.194.10.181:16443` |
| Domain | `dev.resicore.ai` |
| LoadBalancer IP | `172.93.109.158` (Traefik) |
| Storage | Longhorn (default) |
| Context | `microk8s` |
| Namespace | `incore` |
| External URL | `https://dev.resicore.ai/` |

### Configuration Files

| File | Purpose |
|------|---------|
| `values-resicore-ai.yaml` | Main IN-CORE stack (hostname, SSL, storage, passwords, PostgreSQL) |
| `values-geoserver-resicore-ai.yaml` | GeoServer |

### Connection Details

**PostgreSQL**
- Host: `incore-postgresql-hl.incore.svc.cluster.local`
- Port: `5432` | User: `postgres` | Password: see `values-resicore-ai.yaml`

**MongoDB**
- Host: `incore-mongodb.incore.svc.cluster.local`
- Port: `27017` | User: `root` | Password: see `values-resicore-ai.yaml`
- Port-forward: `kubectl port-forward -n incore svc/incore-mongodb 27017:27017 --context microk8s`

**User Approval (incore-approval)**
- **ADMIN_LIST** (approval recipients): `admin@resicore.ai` — admins who receive new-user approval requests
- **EMAIL_FROM**: `no-reply@resicore.ai`
- **New User Alert** (cronjob): `EMAIL_RECIPIENTS: admin@resicore.ai`
- Configured in `values-resicore-ai.yaml` under `approval` and `cronjob.keycloak.new_user_alert`

### Infrastructure (Pre-configured)

- **DNS**: `dev.resicore.ai` → `172.93.109.158`, `172.93.109.160`, `172.93.109.161` (Cloudflare DNS-only)
- **Traefik**: LoadBalancer, ports 80/443
- **cert-manager**: Let's Encrypt, automatic HTTPS
- **MetalLB**: IP pool `172.93.109.158-172.93.109.161`

---

## Prerequisites

- **regcred** secret for pulling images from `hub.ncsa.illinois.edu`:
  ```bash
  kubectl get secret regcred -n incore --context incore-prod -o yaml | kubectl apply -n incore -f -
  ```
- Bitnami Helm repo: `helm repo add bitnami https://charts.bitnami.com/bitnami`

---

## Deployment Steps

### 1. Cluster Context

```bash
kubectl config use-context microk8s
kubectl config set-context --current --namespace=incore
```

### 2. Namespace

```bash
kubectl create namespace incore --dry-run=client -o yaml | kubectl apply -f -
```

### 3. Full IN-CORE Stack

```bash
helm dep build
helm upgrade --install --namespace incore incore . --values values-resicore-ai.yaml
```

Deploys: PostgreSQL, MongoDB, Keycloak, DataWolf, services, playbooks. PostgreSQL is included as a subchart (databases: datawolf, maestro_*). Keycloak uses dev-file database (not PostgreSQL). For database migrations from incore-prod, see [Database Migrations](#database-migrations).

**Verify PostgreSQL**: `kubectl exec incore-postgresql-0 -n incore -- env PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -c "\l"`

---

## GeoServer

**Config**: `values-geoserver-resicore-ai.yaml`

- Image: `hub.ncsa.illinois.edu/incore/geoserver:2.26.1-netcdf`
- Admin: see `values-geoserver-resicore-ai.yaml`
- Protected by incore-auth (Keycloak login required)

```bash
helm repo add ncsa https://opensource.ncsa.illinois.edu/charts/
helm repo update
helm upgrade --install geoserver ncsa/geoserver -n incore -f values-geoserver-resicore-ai.yaml
```

**URL**: https://dev.resicore.ai/geoserver/

---

## incore-auth (Access Control)

Traefik forwardAuth middleware validates Keycloak JWT tokens. Protected resources require IN-CORE login.

| Protected | Path | Unprotected |
|-----------|------|-------------|
| Frontend, Data viewer, DataWolf, Studio, GeoServer, etc. | `/`, `/data/`, `/datawolf/`, `/studio/`, `/geoserver/` | Keycloak `/auth/` |

**Adding protection** (e.g. standalone GeoServer): Add to ingress annotations:
```yaml
traefik.ingress.kubernetes.io/router.middlewares: incore-auth@kubernetescrd
```

## Database Migrations

### DataWolf PostgreSQL Password

resicore-ai uses a different DataWolf password than incore-prod. If database was imported from incore-prod, update the password to match `values-resicore-ai.yaml`:

```bash
# Replace $POSTGRES_PASSWORD and <DATAWOLF_PASSWORD> with values from values-resicore-ai.yaml
kubectl exec -it incore-postgresql-0 -n incore -- env PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -d datawolf -c "ALTER USER datawolf WITH PASSWORD '<DATAWOLF_PASSWORD>';"
kubectl rollout restart deployment/incore-datawolf -n incore
```

**Permission denied for table**: Grant access:
```bash
kubectl exec incore-postgresql-0 -n incore -- env PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -d datawolf -c "
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO datawolf;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO datawolf;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO datawolf;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO datawolf;
"
kubectl rollout restart deployment/incore-datawolf -n incore
```

### MongoDB (incore-prod → microk8s)

1. Get prod password: `kubectl get secret incore-mongodb -n incore --context incore-prod -o jsonpath='{.data.mongodb-root-password}'` (decode base64)
2. Dump: `kubectl exec incore-mongodb-0 -n incore --context incore-prod -- mongodump --db=DBNAME -u root -p $PROD_PWD --authenticationDatabase admin --archive=/tmp/DBNAME.dump`
3. Copy: `kubectl cp incore/incore-mongodb-0:/tmp/DBNAME.dump ./DBNAME.dump --context incore-prod` then `kubectl cp ./DBNAME.dump incore/incore-mongodb-0:/tmp/DBNAME.dump --context microk8s`
4. Restore: `kubectl exec incore-mongodb-0 -n incore --context microk8s -- mongorestore --archive=/tmp/DBNAME.dump -u root -p '$MONGODB_PASSWORD' --authenticationDatabase admin --db=DBNAME`
5. Clean up dumps

**Databases**: spacedb, semanticsdb, projectdb, maestrodb, hazarddb, dfr3db, datadb, commondb

### HazardViewer PREVIEW 404

If HazardViewer PREVIEW returns 404, the hazard references a dataset that is missing from datadb. Restore from incore-prod using scripts in `resicore-docs/`:

```bash
cd resicore-docs
export PROD_PWD="<incore-prod-mongodb-password>"
./export-missing-hazard-datasets-from-prod.sh
./restore-missing-hazard-datasets-to-microk8s.sh
```

See `resicore-docs/RESTORE-MISSING-HAZARD-DATASETS.md` for details. If PREVIEW still fails after restore, the dataset file data may need to be copied from prod (see MIGRATE-DATA-incore-prod-to-microk8s.md).

## Troubleshooting

### Common Commands

```bash
kubectl get pods -n incore
kubectl get svc -n incore
kubectl get pvc -n incore
kubectl get ingress -n incore
kubectl exec incore-postgresql-0 -- env PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -c "SELECT version();"
```

### Log Access

```bash
kubectl logs incore-postgresql-0 -n incore
kubectl logs -n incore -l app.kubernetes.io/name=keycloak -c keycloak
kubectl logs incore-mongodb-0 -n incore
kubectl logs -n incore -l app.kubernetes.io/name=datawolf -c datawolf
kubectl logs -n traefik deployment/traefik
kubectl logs -n cert-manager deployment/cert-manager
```

### Helm: "Request entity too large" (3MB)

Add `*.sql` to `.helmignore` to exclude dump files from the chart package.

### DataWolf: "Connection reset by peer" / "Response is committed"

**Cause**: HTTP probes hit `/datawolf/persons`, which returns 900+ person records. The response is large; the kubelet closes the connection before DataWolf finishes sending it, causing "Connection reset by peer" and "Response is committed, can't handle exception".

**Fix**: Use TCP probes instead of HTTP. `values-resicore-ai.yaml` includes `livenessProbe` and `readinessProbe` overrides for DataWolf using `tcpSocket`—they only check that the port is open, with no HTTP request/response.

### Keycloak: "no available server"

Pod missing `app.kubernetes.io/component=keycloak` label:
```bash
kubectl label pod incore-keycloak-0 app.kubernetes.io/component=keycloak -n incore
```

### Keycloak Admin Console: "Loading the Admin UI" indefinitely

**Causes**: Custom theme conflicts, CSP violations, mixed content (HTTP on HTTPS), wrong `frontendUrl`.

**Fix** (in `values-resicore-ai.yaml`):
- Disable custom theme: `keycloak.initContainers: []`, `extraVolumes: []`, `extraVolumeMounts: []`
- `KC_PROXY: "edge"`, `KC_HOSTNAME_STRICT: "false"`, `KC_HOSTNAME_STRICT_HTTPS: "false"`
- Set CSP frame policies for dev.resicore.ai
- `KEYCLOAK_ADMIN: "keycloak"`
- If migrating: Update `realm_attribute.frontendUrl` to `https://dev.resicore.ai/auth`

### MongoDB: "mongo: executable file not found" (0/1 Ready)

MongoDB 6.0+ uses `mongosh`; Bitnami probes use deprecated `mongo`. Fix: Use custom probes with `mongosh` in `values-resicore-ai.yaml`:

```yaml
mongodb:
  livenessProbe:
    enabled: false
  readinessProbe:
    enabled: false
  customLivenessProbe:
    exec:
      command: [mongosh, --eval, "db.adminCommand('ping')"]
    initialDelaySeconds: 30
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 6
  customReadinessProbe:
    exec:
      command: [mongosh, --eval, "db.adminCommand('ping')"]
    initialDelaySeconds: 5
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 6
```

Then: `kubectl delete pod incore-mongodb-0 -n incore`

---

## PostgreSQL Values Reference

PostgreSQL is configured in `values-resicore-ai.yaml` under the `postgresql` key. Excerpt:

```yaml
# values-resicore-ai.yaml (postgresql section)
postgresql:
  image:
    registry: docker.io
    repository: bitnamilegacy/postgresql
    tag: "16.4.0"
  auth:
    postgresPassword: <set in values-resicore-ai.yaml>
  primary:
    persistence:
      enabled: true
      size: 20Gi
    initdb:
      scripts:
        # keycloak.sql: commented out (Keycloak uses dev-file DB)
        datawolf.sql: |
          CREATE DATABASE datawolf;
          CREATE USER datawolf WITH PASSWORD '<datawolf password>';
          GRANT ALL PRIVILEGES ON DATABASE datawolf TO datawolf;
        maestro.sql: |
          CREATE DATABASE maestro_galveston;
          CREATE DATABASE maestro_joplin;
          CREATE DATABASE maestro_slc;
          CREATE USER maestro WITH PASSWORD '<maestro password>';
          GRANT ALL PRIVILEGES ON DATABASE maestro_galveston TO maestro;
          GRANT ALL PRIVILEGES ON DATABASE maestro_joplin TO maestro;
          GRANT ALL PRIVILEGES ON DATABASE maestro_slc TO maestro;
  resources:
    limits: { cpu: "2", memory: 4Gi }
    requests: { cpu: "1", memory: 2Gi }
```

---

## Notes

- Passwords configured in values files (do not commit secrets)
- Storage: Longhorn, automatic provisioning
- HTTPS: cert-manager + Let's Encrypt
- Services: 1 replica each (scaled down)
- Bitnami legacy images for compatibility
- DataWolf chart modified locally; avoid `helm dependency update` for datawolf

---
**Last Updated**: March 4, 2026 | **Cluster**: MicroK8s (resicore.ai)
