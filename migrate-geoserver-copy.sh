#!/bin/bash
# Migrate GeoServer: copy ONLY base structure + ergo/incore layer dirs (selective, saves disk space)
# Run from tmp/: bash ../migrate-geoserver-copy.sh
#
# Prereq: geoserver-dataset-ids.txt (from migrate-geoserver-dataset-ids.js on incore-prod)
# Prereq: Verify GeoServer data path: kubectl exec deployment/geoserver -n incore --context incore-prod -- ls /opt/geoserver_data
# If path differs: export GEO_BASE=/path/to/geoserver_data
#
# Password: security/ is excluded so microk8s keeps the password from values-geoserver-resicore-ai.yaml
# URLs: prod hostnames in XML are replaced with TARGET_HOST (default dev.resicore.ai)
#   Override: TARGET_HOST=myhost.example.com

set -e
GEO_BASE="${GEO_BASE:-/opt/geoserver_data}"
TARGET_HOST="${TARGET_HOST:-dev.resicore.ai}"
PROD_POD=$(kubectl get pods -n incore --context incore-prod -l app.kubernetes.io/name=geoserver -o jsonpath='{.items[0].metadata.name}')
MICROK8S_POD=$(kubectl get pods -n incore --context microk8s -l app.kubernetes.io/name=geoserver -o jsonpath='{.items[0].metadata.name}')

[[ -z "$PROD_POD" ]] && { echo "ERROR: No incore-prod geoserver pod"; exit 1; }
[[ -z "$MICROK8S_POD" ]] && { echo "ERROR: No microk8s geoserver pod"; exit 1; }
[[ ! -f geoserver-dataset-ids.txt ]] && { echo "ERROR: Run Step 1 first to create geoserver-dataset-ids.txt"; exit 1; }

# Build keep set (ergo/incore dataset IDs)
declare -A KEEP_IDS
while IFS= read -r dsId || [[ -n "$dsId" ]]; do
  dsId=$(echo "$dsId" | tr -d '\r')
  [[ "$dsId" =~ ^[a-f0-9]{24}$ ]] && KEEP_IDS[$dsId]=1
done < geoserver-dataset-ids.txt

echo "Keep set: ${#KEEP_IDS[@]} dataset IDs (ergo/incore)"

mkdir -p migration-geoserver
rm -rf migration-geoserver/*

echo ""
echo "Phase 1: Getting layer dir list from prod (to build exclude list)..."
# Find layer dirs on prod; output paths relative to GEO_BASE
GEO_PARENT=$(dirname "$GEO_BASE")
GEO_NAME=$(basename "$GEO_BASE")
LAYER_PATTERN='[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]'
# Exclude paths must match archive paths (we tar from parent, so paths are ${GEO_NAME}/...)
kubectl exec -n incore "$PROD_POD" --context incore-prod -- sh -c "cd ${GEO_BASE} && find . -type d -name '${LAYER_PATTERN}' -print 2>/dev/null" 2>/dev/null | sed 's|^\./||' | while IFS= read -r relpath; do
  [[ -z "$relpath" ]] && continue
  name=$(basename "$relpath")
  [[ -n "${KEEP_IDS[$name]}" ]] && continue
  echo "${GEO_NAME}/${relpath}"
done > exclude-layers.txt 2>/dev/null || true

excludecount=$(wc -l < exclude-layers.txt 2>/dev/null || echo 0)
echo "  Excluding $excludecount layer dirs (not in ergo/incore)"

echo ""
echo "Phase 2: Copying from prod (base + ergo/incore layers only, excludes ${excludecount} dirs)..."
# Copy exclude list to pod, then tar with --exclude-from
kubectl cp exclude-layers.txt "incore/${PROD_POD}:/tmp/geoserver-exclude.txt" --context incore-prod 2>/dev/null
kubectl exec -n incore "$PROD_POD" --context incore-prod -- sh -c "cd ${GEO_PARENT} && tar czf - --exclude-from=/tmp/geoserver-exclude.txt --exclude='${GEO_NAME}/security' ${GEO_NAME}" 2>/dev/null | tar xzf - -C migration-geoserver --strip-components=1 2>/dev/null

echo "  Copied. Size: $(du -sh migration-geoserver | cut -f1)"

echo ""
echo "Phase 3: Fixing hardcoded URLs in XML/properties files..."
fixcount=0
for f in $(find migration-geoserver -type f \( -name "*.xml" -o -name "*.properties" \) 2>/dev/null); do
  if grep -qE 'tools\.in-core\.org|dev\.in-core\.org' "$f" 2>/dev/null; then
    perl -i -pe "s|https://tools\.in-core\.org/geoserver|https://${TARGET_HOST}/geoserver|g; s|https://dev\.in-core\.org/geoserver|https://${TARGET_HOST}/geoserver|g; s|http://tools\.in-core\.org/geoserver|https://${TARGET_HOST}/geoserver|g; s|http://dev\.in-core\.org/geoserver|https://${TARGET_HOST}/geoserver|g; s|tools\.in-core\.org|${TARGET_HOST}|g; s|dev\.in-core\.org|${TARGET_HOST}|g" "$f" 2>/dev/null
    ((fixcount++)) || true
  fi
done
echo "  Updated $fixcount files with ${TARGET_HOST}"

echo ""
echo "Phase 4: Creating tar and copying to microk8s..."
cd migration-geoserver
tar czf ../geoserver-data.tar.gz .
cd ..
echo "  Tar created ($(du -h geoserver-data.tar.gz | cut -f1))"

echo "  Copying tar to pod..."
kubectl cp geoserver-data.tar.gz "incore/${MICROK8S_POD}:/tmp/geoserver-data.tar.gz" --context microk8s

echo "  Extracting on pod (merge into existing data_dir)..."
kubectl exec -n incore "${MICROK8S_POD}" --context microk8s -- sh -c "cd ${GEO_BASE} && tar xzf /tmp/geoserver-data.tar.gz && rm /tmp/geoserver-data.tar.gz"

# Cleanup
rm -f exclude-layers.txt

echo ""
echo "Done. Restart GeoServer if needed: kubectl rollout restart deployment/geoserver -n incore --context microk8s"
