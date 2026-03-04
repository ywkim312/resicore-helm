# IN-CORE (resicore-helm)

[IN-CORE](https://incore.ncsa.illinois.edu/) enables scientific analyses that model the impact of natural hazards on communities and their resilience. This platform runs on Kubernetes with Docker containers.

## Forking / Origin

This repository (**resicore-helm**) was forked from [incore-helm](https://github.com/IN-CORE/incore-helm). It is configured for deployment on the resicore.ai MicroK8s cluster.

| Values File | Purpose |
|-------------|---------|
| `values-resicore-ai.yaml` | Main IN-CORE stack (MongoDB, Keycloak, DataWolf, services, playbooks) |
| `values-jupyterhub-resicore-ai.yaml` | JupyterHub (incore-lab) |
| `values-geoserver-resicore-ai.yaml` | GeoServer for spatial services |

## Documentation

| Document | Description |
|----------|-------------|
| [DEPLOYMENT-RESICORE-AI.md](DEPLOYMENT-RESICORE-AI.md) | Full deployment guide for resicore.ai |
| [GEOSERVER-MIGRATION.md](GEOSERVER-MIGRATION.md) | GeoServer data migration from incore-prod |
| [ISSUE-logout-redirect.md](ISSUE-logout-redirect.md) | Logout redirect issue (frontend fix) |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

## Quick Start (resicore.ai)

```bash
# 1. Create namespace and deploy PostgreSQL (create postgresql-values.yaml — see DEPLOYMENT-RESICORE-AI.md)
kubectl create namespace incore --dry-run=client -o yaml | kubectl apply -f -
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install incore-postgresql bitnami/postgresql -n incore --values postgresql-values.yaml

# 2. Deploy IN-CORE stack
helm upgrade --install --namespace incore incore . --values values-resicore-ai.yaml

# 3. Deploy JupyterHub (optional)
helm upgrade --install jupyterhub jupyterhub/jupyterhub -n incore -f values-jupyterhub-resicore-ai.yaml --version 3.3.8

# 4. Deploy GeoServer (optional)
helm repo add ncsa https://opensource.ncsa.illinois.edu/charts/
helm upgrade --install geoserver ncsa/geoserver -n incore -f values-geoserver-resicore-ai.yaml
```

**Prerequisites**: `regcred` secret for `hub.ncsa.illinois.edu`, cluster context `microk8s`. See [DEPLOYMENT-RESICORE-AI.md](DEPLOYMENT-RESICORE-AI.md) for details.

## Upstream (IN-CORE)

For the original NCSA chart:

```bash
helm repo add ncsa https://opensource.ncsa.illinois.edu/charts/
helm install incore ncsa/incore
```

## Prerequisites

- Kubernetes 1.16+
- Helm 3
- PV provisioner support (Longhorn on resicore.ai)

## Configuration

See [values.yaml](values.yaml) for all options. Key parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| ingress.hosts[0].host | Ingress hostname | incore.example.com |
| ingress.traefik | Use Traefik V2 middleware | false |

Use YAML anchors for hostname consistency:

```yaml
hostname: &hostname dev.resicore.ai
ingress:
  hosts:
    - host: *hostname
keycloak:
  ingress:
    rules:
      - host: *hostname
        paths:
          - /auth/
```

## Persistence

IN-CORE uses persistent storage for uploaded and generated data. For existing PVCs, see [incore-pvc.yaml](incore-pvc.yaml).
