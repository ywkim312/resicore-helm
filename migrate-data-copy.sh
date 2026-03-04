#!/bin/bash
# Migrate ergo/incore data files from incore-prod to microk8s
# Run from tmp/ with: bash ../migrate-data-copy.sh
#
# Phase 1: Copy prod -> local (per path)
# Phase 2: Tar local, copy single file to pod, extract (avoids per-path kubectl cp to pod issues)

set -e
PROD_POD=$(kubectl get pods -n incore --context incore-prod -l app.kubernetes.io/name=incore-svc-data -o jsonpath='{.items[0].metadata.name}')
MICROK8S_POD=$(kubectl get pods -n incore --context microk8s -l app.kubernetes.io/name=incore-svc-data -o jsonpath='{.items[0].metadata.name}')

[[ -z "$PROD_POD" ]] && { echo "ERROR: No incore-prod data pod"; exit 1; }
[[ -z "$MICROK8S_POD" ]] && { echo "ERROR: No microk8s data pod"; exit 1; }
[[ ! -f ergo-incore-paths.txt ]] && { echo "ERROR: Run Step 1 first to create ergo-incore-paths.txt"; exit 1; }

mkdir -p migration-data/data
count=0
fail=0

echo "Phase 1: Copying from incore-prod to local..."
while IFS= read -r path || [[ -n "$path" ]]; do
  path=$(echo "$path" | tr -d '\r')
  [[ -z "$path" ]] && continue
  path="${path#/home/incore/data/}"
  [[ -z "$path" ]] && continue

  parent_dir=$(dirname "$path")
  dir_name=$(basename "$path")
  mkdir -p "migration-data/data/$parent_dir"

  if ! kubectl cp "incore/${PROD_POD}:/home/incore/data/${path}" "migration-data/data/${parent_dir}/" --context incore-prod 2>/dev/null; then
    echo "FAIL prod: $path"
    ((fail++)) || true
    continue
  fi

  ((count++)) || true
  [[ $((count % 200)) -eq 0 ]] && echo "  Copied $count from prod..."
done < ergo-incore-paths.txt

echo "Phase 1 done. Copied $count from prod, $fail failed."

echo ""
echo "Phase 2: Creating tar and copying to microk8s..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(pwd)"
cd migration-data/data
tar czf ../data.tar.gz .
cd "$WORK_DIR"
echo "  Tar created ($(du -h migration-data/data.tar.gz | cut -f1))"

echo "  Copying tar to pod..."
kubectl cp migration-data/data.tar.gz "incore/${MICROK8S_POD}:/tmp/data.tar.gz" --context microk8s

echo "  Extracting on pod..."
kubectl exec -n incore "${MICROK8S_POD}" --context microk8s -- sh -c "cd /home/incore/data && tar xzf /tmp/data.tar.gz && rm /tmp/data.tar.gz"

echo ""
echo "Done. Verify with:"
echo "  kubectl exec -n incore deployment/incore-svc-data --context microk8s -- sh -c 'find /home/incore/data -type f | wc -l'"
